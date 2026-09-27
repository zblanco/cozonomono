defmodule Cozonomono.LazyRows do
  @moduledoc """
  A lazy, zero-copy reference to CozoDB query results.

  Unlike `%NamedRows{}` which eagerly copies all data from the Rust heap into
  BEAM terms, `%LazyRows{}` holds an opaque reference to the results on the
  Rust heap. Data is only copied when you access it via the accessor functions.

  This is ideal for large result sets where you only need a subset of rows
  or columns, or when passing results between NIF calls.

  ## Metadata fields (no NIF call needed)

    * `headers` - list of column name strings
    * `row_count` - number of rows in this statement's result
    * `column_count` - number of columns
    * `has_next` - whether there is a next statement result in the chain

  ## Enumeration

  `LazyRows` does **not** implement `Enumerable` directly — this is intentional.
  Each NIF boundary crossing has overhead (~2-3μs), so naïve per-row iteration
  would add significant cost for large result sets. Instead, use:

    * `to_enum/1` — returns an iterator struct implementing `Enumerable` with a
      chunked `slice` callback that amortizes NIF cost (one call per 1000 rows)
    * `to_stream/2` — returns an Elixir `Stream` that pulls rows in configurable
      chunks, bounding memory usage for very large results

  ## Examples

      {:ok, lazy} = Cozonomono.query_lazy(instance, "?[id, name] := *users{id, name}")
      lazy.row_count     #=> 10000
      lazy.headers       #=> ["id", "name"]

      # Access individual cells without copying everything
      {:ok, cell} = Cozonomono.LazyRows.cell_at(lazy, 0, 0)

      # Pipe into Enum via to_enum (chunked NIF calls)
      names = lazy |> Cozonomono.LazyRows.to_enum() |> Enum.map(&Enum.at(&1, 1))

      # Stream rows in bounded-memory chunks
      lazy |> Cozonomono.LazyRows.to_stream(chunk_size: 500) |> Stream.take(10) |> Enum.to_list()

      # Materialize when you need the full result
      %Cozonomono.NamedRows{} = Cozonomono.LazyRows.to_named_rows(lazy)
  """

  alias Cozonomono.Native

  defstruct [:resource, :statement_index, :headers, :row_count, :column_count, :has_next]

  @type t :: %__MODULE__{
          resource: reference(),
          statement_index: non_neg_integer(),
          headers: [String.t()],
          row_count: non_neg_integer(),
          column_count: non_neg_integer(),
          has_next: boolean()
        }

  @doc """
  Returns the next statement's lazy result in a multi-statement chain.

  Returns `{:ok, %LazyRows{}}` or `{:error, :out_of_bounds}` if there is no next.
  """
  @spec next(t()) :: {:ok, t()} | {:error, :out_of_bounds}
  def next(%__MODULE__{} = lazy) do
    case Native.lazy_rows_next(lazy) do
      {:ok, next_lazy} -> {:ok, next_lazy}
      {:error, :out_of_bounds} -> {:error, :out_of_bounds}
    end
  end

  @doc """
  Returns a single row at the given index as a list of values.

  Returns `{:ok, row}` or `{:error, :out_of_bounds}`.
  """
  @spec row_at(t(), non_neg_integer()) :: {:ok, [term()]} | {:error, :out_of_bounds}
  def row_at(%__MODULE__{} = lazy, index) when is_integer(index) and index >= 0 do
    case Native.lazy_rows_row_at(lazy, index) do
      {:ok, row} -> {:ok, row}
      {:error, :out_of_bounds} -> {:error, :out_of_bounds}
    end
  end

  @doc """
  Returns a single cell value at the given row and column indices.

  Returns `{:ok, value}` or `{:error, :out_of_bounds}`.
  """
  @spec cell_at(t(), non_neg_integer(), non_neg_integer()) ::
          {:ok, term()} | {:error, :out_of_bounds}
  def cell_at(%__MODULE__{} = lazy, row_index, col_index)
      when is_integer(row_index) and row_index >= 0 and
             is_integer(col_index) and col_index >= 0 do
    case Native.lazy_rows_cell_at(lazy, row_index, col_index) do
      {:ok, value} -> {:ok, value}
      {:error, :out_of_bounds} -> {:error, :out_of_bounds}
    end
  end

  @doc """
  Returns all values for a column by index as a list.

  Returns `{:ok, values}` or `{:error, :out_of_bounds}`.
  """
  @spec column_at(t(), non_neg_integer()) :: {:ok, [term()]} | {:error, :out_of_bounds}
  def column_at(%__MODULE__{} = lazy, col_index) when is_integer(col_index) and col_index >= 0 do
    case Native.lazy_rows_column_at(lazy, col_index) do
      {:ok, values} -> {:ok, values}
      {:error, :out_of_bounds} -> {:error, :out_of_bounds}
    end
  end

  @doc """
  Returns all values for a column by name as a list.

  Returns `{:ok, values}` or raises `ArgumentError` if the column name is unknown.
  """
  @spec column(t(), String.t()) :: {:ok, [term()]} | {:error, :out_of_bounds}
  def column(%__MODULE__{headers: headers} = lazy, name) when is_binary(name) do
    case Enum.find_index(headers, &(&1 == name)) do
      nil -> raise ArgumentError, "unknown column #{inspect(name)}"
      idx -> column_at(lazy, idx)
    end
  end

  @doc """
  Returns a slice of rows starting at `offset` with `length` rows.

  Returns `{:ok, rows}` where rows is a list of row lists.
  Returns `{:error, :out_of_bounds}` if offset is past the end.
  If `offset + length` exceeds the row count, returns rows up to the end.
  """
  @spec slice(t(), non_neg_integer(), non_neg_integer()) ::
          {:ok, [[term()]]} | {:error, :out_of_bounds}
  def slice(%__MODULE__{} = lazy, offset, length)
      when is_integer(offset) and offset >= 0 and
             is_integer(length) and length >= 0 do
    case Native.lazy_rows_slice(lazy, offset, length) do
      {:ok, rows} -> {:ok, rows}
      {:error, :out_of_bounds} -> {:error, :out_of_bounds}
    end
  end

  @doc """
  Fully materializes the lazy result into a `%NamedRows{}` struct.

  This copies all data from the Rust heap to the BEAM, equivalent to
  what `query/3` does eagerly.
  """
  @spec to_named_rows(t()) :: Cozonomono.NamedRows.t()
  def to_named_rows(%__MODULE__{} = lazy) do
    Native.lazy_rows_to_named_rows(lazy)
  end

  @doc """
  Returns an `Enumerable` iterator over rows.

  The returned struct implements `Enumerable` with a chunked `slice` callback,
  so `Enum` functions that can use slice access (like `Enum.take/2`, `Enum.at/2`)
  make a single bulk NIF call. General iteration via `reduce` fetches rows in
  chunks of 1000 to amortize NIF boundary crossing overhead.

  Prefer `column_at/2`, `slice/3`, or `to_named_rows/1` when you know what
  data you need — they make fewer NIF calls. Use `to_enum/1` when you want
  compatibility with arbitrary `Enum` functions.

  ## Examples

      {:ok, lazy} = Cozonomono.query_lazy(instance, "?[id, name] := *users{id, name}")

      # Enum.take uses the slice callback → one NIF call
      first_five = lazy |> Cozonomono.LazyRows.to_enum() |> Enum.take(5)

      # Enum.map iterates in 1000-row chunks internally
      ids = lazy |> Cozonomono.LazyRows.to_enum() |> Enum.map(&hd/1)
  """
  @spec to_enum(t()) :: Enumerable.t()
  def to_enum(%__MODULE__{} = lazy) do
    Cozonomono.LazyRows.Iterator.new(lazy)
  end

  @doc """
  Returns an Elixir `Stream` that yields rows in bounded-memory chunks.

  Each chunk fetches `chunk_size` rows in a single NIF call, so at most
  `chunk_size` rows are materialized on the BEAM heap at any time. This is
  the right choice for processing very large result sets without loading
  everything into memory at once.

  ## Options

    * `chunk_size` — number of rows per NIF call (default: `1000`)

  ## Examples

      {:ok, lazy} = Cozonomono.query_lazy(instance, "?[id, name] := *users{id, name}")

      # Process 100k rows with at most 500 in memory
      lazy
      |> Cozonomono.LazyRows.to_stream(chunk_size: 500)
      |> Stream.filter(fn [_id, name] -> String.starts_with?(name, "A") end)
      |> Enum.to_list()
  """
  @spec to_stream(t(), keyword()) :: Enumerable.t()
  def to_stream(%__MODULE__{} = lazy, opts \\ []) do
    chunk_size = Keyword.get(opts, :chunk_size, 1000)
    total = lazy.row_count

    Stream.resource(
      fn -> 0 end,
      fn
        offset when offset >= total ->
          {:halt, offset}

        offset ->
          len = min(chunk_size, total - offset)
          {:ok, rows} = slice(lazy, offset, len)
          {rows, offset + len}
      end,
      fn _offset -> :ok end
    )
  end
end
