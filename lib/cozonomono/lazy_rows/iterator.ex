defmodule Cozonomono.LazyRows.Iterator do
  @moduledoc false

  # Private iterator struct returned by `LazyRows.to_enum/1`.
  # Implements `Enumerable` with a bulk `slice` callback that uses
  # `lazy_rows_slice` (one NIF call per chunk) instead of per-element access.

  alias Cozonomono.LazyRows

  defstruct [:lazy_rows]

  @opaque t :: %__MODULE__{lazy_rows: LazyRows.t()}

  def new(%LazyRows{} = lazy_rows), do: %__MODULE__{lazy_rows: lazy_rows}

  defimpl Enumerable do
    def count(%{lazy_rows: %{row_count: n}}), do: {:ok, n}

    # O(n) linear scan is misleading for NIF-backed data; let Enum fall back
    # to reduce-based membership test so the cost is visible.
    def member?(_iterator, _value), do: {:error, __MODULE__}

    def slice(%{lazy_rows: %{row_count: size} = lazy}) do
      {:ok, size,
       fn start, length, step ->
         {:ok, rows} = LazyRows.slice(lazy, start, length)

         if step == 1 do
           rows
         else
           rows |> Enum.take_every(step)
         end
       end}
    end

    def reduce(%{lazy_rows: lazy}, acc, fun) do
      reduce_rows(lazy, lazy.row_count, 0, acc, fun)
    end

    # Chunked reduce: fetches @chunk_size rows per NIF call instead of one-by-one.
    # Each NIF crossing has ~2-3μs overhead, so 100k rows at 1-per-call = ~250ms
    # in crossing cost alone. With 1000-row chunks, that drops to ~100 calls.
    @chunk_size 1000

    defp reduce_rows(_lazy, _size, _offset, {:halt, acc}, _fun), do: {:halted, acc}

    defp reduce_rows(lazy, size, offset, {:suspend, acc}, fun) do
      {:suspended, acc, &reduce_rows(lazy, size, offset, &1, fun)}
    end

    defp reduce_rows(_lazy, size, offset, {:cont, acc}, _fun) when offset >= size do
      {:done, acc}
    end

    defp reduce_rows(lazy, size, offset, {:cont, acc}, fun) do
      chunk_len = min(@chunk_size, size - offset)
      {:ok, rows} = LazyRows.slice(lazy, offset, chunk_len)
      reduce_chunk(rows, lazy, size, offset + chunk_len, {:cont, acc}, fun)
    end

    defp reduce_chunk([], lazy, size, offset, acc, fun) do
      reduce_rows(lazy, size, offset, acc, fun)
    end

    defp reduce_chunk([row | rest], lazy, size, offset, {:cont, acc}, fun) do
      reduce_chunk(rest, lazy, size, offset, fun.(row, acc), fun)
    end

    defp reduce_chunk(_rest, _lazy, _size, _offset, {:halt, acc}, _fun) do
      {:halted, acc}
    end

    defp reduce_chunk(rest, lazy, size, offset, {:suspend, acc}, fun) do
      {:suspended, acc, &reduce_chunk(rest, lazy, size, offset, &1, fun)}
    end
  end
end
