defmodule Cozonomono.LazyRowsTest do
  use ExUnit.Case
  alias Cozonomono.LazyRows
  alias Cozonomono.NamedRows

  setup do
    {:ok, instance} = Cozonomono.new()

    {:ok, _} =
      Cozonomono.query(
        instance,
        ":create users {id: Int => name: String, score: Float}"
      )

    rows =
      Enum.map(1..100, fn i ->
        "[#{i}, 'User_#{i}', #{i * 1.5}]"
      end)

    {:ok, _} =
      Cozonomono.query(
        instance,
        "?[id, name, score] <- [#{Enum.join(rows, ", ")}] :put users {id => name, score}"
      )

    {:ok, instance: instance}
  end

  describe "query_lazy/3" do
    test "returns a LazyRows struct with metadata", %{instance: instance} do
      {:ok, lazy} =
        Cozonomono.query_lazy(instance, "?[id, name, score] := *users{id, name, score}")

      assert %LazyRows{} = lazy
      assert lazy.headers == ["id", "name", "score"]
      assert lazy.row_count == 100
      assert lazy.column_count == 3
      assert lazy.has_next == false
    end

    test "works with params", %{instance: instance} do
      {:ok, lazy} =
        Cozonomono.query_lazy(
          instance,
          "?[id, name, score] := *users{id, name, score}, id == $target",
          params: %{"target" => 42}
        )

      assert lazy.row_count == 1
    end

    test "works with inline data", %{instance: instance} do
      {:ok, lazy} =
        Cozonomono.query_lazy(instance, "?[] <- [['hello', 'world', 42]]")

      assert lazy.headers == ["_0", "_1", "_2"]
      assert lazy.row_count == 1
      assert lazy.column_count == 3
    end
  end

  describe "row_at/2" do
    test "returns a single row by index", %{instance: instance} do
      {:ok, lazy} =
        Cozonomono.query_lazy(instance, "?[id, name, score] := *users{id, name, score}, id == 1")

      assert {:ok, [1, "User_1", 1.5]} = LazyRows.row_at(lazy, 0)
    end

    test "returns error for out of bounds", %{instance: instance} do
      {:ok, lazy} =
        Cozonomono.query_lazy(instance, "?[id, name, score] := *users{id, name, score}, id == 1")

      assert {:error, :out_of_bounds} = LazyRows.row_at(lazy, 999)
    end
  end

  describe "cell_at/3" do
    test "returns a single cell value", %{instance: instance} do
      {:ok, lazy} =
        Cozonomono.query_lazy(instance, "?[id, name, score] := *users{id, name, score}, id == 1")

      assert {:ok, 1} = LazyRows.cell_at(lazy, 0, 0)
      assert {:ok, "User_1"} = LazyRows.cell_at(lazy, 0, 1)
      assert {:ok, 1.5} = LazyRows.cell_at(lazy, 0, 2)
    end

    test "returns error for out of bounds row", %{instance: instance} do
      {:ok, lazy} =
        Cozonomono.query_lazy(instance, "?[id, name, score] := *users{id, name, score}, id == 1")

      assert {:error, :out_of_bounds} = LazyRows.cell_at(lazy, 999, 0)
    end

    test "returns error for out of bounds column", %{instance: instance} do
      {:ok, lazy} =
        Cozonomono.query_lazy(instance, "?[id, name, score] := *users{id, name, score}, id == 1")

      assert {:error, :out_of_bounds} = LazyRows.cell_at(lazy, 0, 999)
    end
  end

  describe "column_at/2" do
    test "returns all values for a column", %{instance: instance} do
      {:ok, lazy} =
        Cozonomono.query_lazy(
          instance,
          "?[id, name, score] := *users{id, name, score}, id <= 3 :sort id"
        )

      assert {:ok, [1, 2, 3]} = LazyRows.column_at(lazy, 0)
      assert {:ok, ["User_1", "User_2", "User_3"]} = LazyRows.column_at(lazy, 1)
    end

    test "returns error for out of bounds", %{instance: instance} do
      {:ok, lazy} =
        Cozonomono.query_lazy(instance, "?[id, name, score] := *users{id, name, score}, id == 1")

      assert {:error, :out_of_bounds} = LazyRows.column_at(lazy, 999)
    end
  end

  describe "column/2" do
    test "returns column values by name", %{instance: instance} do
      {:ok, lazy} =
        Cozonomono.query_lazy(
          instance,
          "?[id, name, score] := *users{id, name, score}, id <= 3 :sort id"
        )

      assert {:ok, ["User_1", "User_2", "User_3"]} = LazyRows.column(lazy, "name")
    end

    test "raises for unknown column name", %{instance: instance} do
      {:ok, lazy} =
        Cozonomono.query_lazy(instance, "?[id, name, score] := *users{id, name, score}")

      assert_raise ArgumentError, ~r/unknown column/, fn ->
        LazyRows.column(lazy, "nonexistent")
      end
    end
  end

  describe "slice/3" do
    test "returns a slice of rows", %{instance: instance} do
      {:ok, lazy} =
        Cozonomono.query_lazy(
          instance,
          "?[id, name, score] := *users{id, name, score} :sort id"
        )

      {:ok, rows} = LazyRows.slice(lazy, 0, 3)
      assert length(rows) == 3
      assert Enum.at(rows, 0) == [1, "User_1", 1.5]
      assert Enum.at(rows, 1) == [2, "User_2", 3.0]
      assert Enum.at(rows, 2) == [3, "User_3", 4.5]
    end

    test "clamps to available rows when length exceeds count", %{instance: instance} do
      {:ok, lazy} =
        Cozonomono.query_lazy(
          instance,
          "?[id, name, score] := *users{id, name, score}, id <= 3 :sort id"
        )

      {:ok, rows} = LazyRows.slice(lazy, 1, 100)
      assert length(rows) == 2
    end

    test "returns error when offset is past end", %{instance: instance} do
      {:ok, lazy} =
        Cozonomono.query_lazy(
          instance,
          "?[id, name, score] := *users{id, name, score}, id <= 3"
        )

      assert {:error, :out_of_bounds} = LazyRows.slice(lazy, 999, 1)
    end
  end

  describe "to_named_rows/1" do
    test "materializes full result", %{instance: instance} do
      {:ok, lazy} =
        Cozonomono.query_lazy(
          instance,
          "?[id, name, score] := *users{id, name, score}, id <= 3 :sort id"
        )

      result = LazyRows.to_named_rows(lazy)
      assert %NamedRows{} = result
      assert result.headers == ["id", "name", "score"]
      assert length(result.rows) == 3
      assert Enum.at(result.rows, 0) == [1, "User_1", 1.5]
    end

    test "matches eager query result", %{instance: instance} do
      query = "?[id, name, score] := *users{id, name, score} :sort id"

      {:ok, eager} = Cozonomono.query(instance, query)
      {:ok, lazy} = Cozonomono.query_lazy(instance, query)
      materialized = LazyRows.to_named_rows(lazy)

      assert eager.headers == materialized.headers
      assert eager.rows == materialized.rows
      assert eager.next == materialized.next
    end
  end

  describe "next chain" do
    test "single statement has no next" do
      {:ok, instance} = Cozonomono.new()

      {:ok, lazy} =
        Cozonomono.query_lazy(instance, "?[] <- [[1]]")

      assert lazy.has_next == false
      assert {:error, :out_of_bounds} = LazyRows.next(lazy)
    end

    test "imperative block returns last result only", %{instance: instance} do
      {:ok, lazy} =
        Cozonomono.query_lazy(instance, """
        {?[id, name, score] <- [[999, 'Test', 0.0]] :put users {id => name, score}}
        {?[id, name, score] := *users{id, name, score}, id == 999}
        """)

      # CozoDB imperative blocks return only the last statement result
      assert lazy.row_count == 1
      {:ok, row} = LazyRows.row_at(lazy, 0)
      assert row == [999, "Test", 0.0]
    end
  end

  describe "tx_query_lazy/3" do
    test "works within a transaction", %{instance: instance} do
      {:ok, tx} = Cozonomono.multi_transaction(instance)

      {:ok, lazy} =
        Cozonomono.tx_query_lazy(
          tx,
          "?[id, name, score] := *users{id, name, score}, id <= 5 :sort id"
        )

      assert lazy.row_count == 5
      {:ok, row} = LazyRows.row_at(lazy, 0)
      assert row == [1, "User_1", 1.5]

      :ok = Cozonomono.tx_abort(tx)
    end
  end

  describe "resource lifetime" do
    test "lazy result works after instance is closed" do
      {:ok, instance} = Cozonomono.new()

      {:ok, _} =
        Cozonomono.query(
          instance,
          "?[id, name] <- [[1, 'Alice']] :create test {id: Int => name: String}"
        )

      {:ok, lazy} = Cozonomono.query_lazy(instance, "?[id, name] := *test{id, name}")

      :ok = Cozonomono.close(instance)

      # Lazy result should still be accessible after close since it owns the data
      assert {:ok, [1, "Alice"]} = LazyRows.row_at(lazy, 0)
    end
  end

  describe "data types through lazy" do
    test "handles diverse data types", %{instance: instance} do
      {:ok, lazy} =
        Cozonomono.query_lazy(instance, "?[] <- [[null, true, false, 42, 3.14, 'hello', [1, 2]]]")

      {:ok, row} = LazyRows.row_at(lazy, 0)
      assert row == [nil, true, false, 42, 3.14, "hello", [1, 2]]
    end
  end

  describe "to_enum/1" do
    test "Enum.count uses count callback", %{instance: instance} do
      {:ok, lazy} =
        Cozonomono.query_lazy(instance, "?[id, name, score] := *users{id, name, score}")

      assert Enum.count(LazyRows.to_enum(lazy)) == 100
    end

    test "Enum.take uses slice callback", %{instance: instance} do
      {:ok, lazy} =
        Cozonomono.query_lazy(
          instance,
          "?[id, name, score] := *users{id, name, score} :sort id"
        )

      rows = lazy |> LazyRows.to_enum() |> Enum.take(3)
      assert length(rows) == 3
      assert Enum.at(rows, 0) == [1, "User_1", 1.5]
      assert Enum.at(rows, 1) == [2, "User_2", 3.0]
      assert Enum.at(rows, 2) == [3, "User_3", 4.5]
    end

    test "Enum.at uses slice callback", %{instance: instance} do
      {:ok, lazy} =
        Cozonomono.query_lazy(
          instance,
          "?[id, name, score] := *users{id, name, score} :sort id"
        )

      row = lazy |> LazyRows.to_enum() |> Enum.at(49)
      assert row == [50, "User_50", 75.0]
    end

    test "Enum.map iterates all rows via chunked reduce", %{instance: instance} do
      {:ok, lazy} =
        Cozonomono.query_lazy(instance, "?[id, name, score] := *users{id, name, score}")

      ids = lazy |> LazyRows.to_enum() |> Enum.map(&hd/1) |> Enum.sort()
      assert ids == Enum.to_list(1..100)
    end

    test "Enum.reduce with early halt", %{instance: instance} do
      {:ok, lazy} =
        Cozonomono.query_lazy(
          instance,
          "?[id, name, score] := *users{id, name, score} :sort id"
        )

      # Take first 3 ids via reduce
      {ids, _} =
        lazy
        |> LazyRows.to_enum()
        |> Enum.reduce_while({[], 0}, fn row, {acc, count} ->
          if count < 3, do: {:cont, {[hd(row) | acc], count + 1}}, else: {:halt, {acc, count}}
        end)

      assert Enum.sort(ids) == [1, 2, 3]
    end

    test "Enum.to_list returns all rows", %{instance: instance} do
      {:ok, lazy} =
        Cozonomono.query_lazy(
          instance,
          "?[id, name, score] := *users{id, name, score}, id <= 5 :sort id"
        )

      rows = lazy |> LazyRows.to_enum() |> Enum.to_list()
      assert length(rows) == 5
      assert Enum.at(rows, 0) == [1, "User_1", 1.5]
    end

    test "empty result set", %{instance: instance} do
      {:ok, lazy} =
        Cozonomono.query_lazy(
          instance,
          "?[id, name, score] := *users{id, name, score}, id > 9999"
        )

      assert Enum.count(LazyRows.to_enum(lazy)) == 0
      assert Enum.to_list(LazyRows.to_enum(lazy)) == []
    end

    test "works with Enum.zip", %{instance: instance} do
      {:ok, lazy} =
        Cozonomono.query_lazy(
          instance,
          "?[id, name, score] := *users{id, name, score}, id <= 3 :sort id"
        )

      zipped = lazy |> LazyRows.to_enum() |> Enum.zip([:a, :b, :c])

      assert zipped == [
               {[1, "User_1", 1.5], :a},
               {[2, "User_2", 3.0], :b},
               {[3, "User_3", 4.5], :c}
             ]
    end
  end

  describe "to_stream/2" do
    test "streams all rows with default chunk_size", %{instance: instance} do
      {:ok, lazy} =
        Cozonomono.query_lazy(instance, "?[id, name, score] := *users{id, name, score}")

      rows = lazy |> LazyRows.to_stream() |> Enum.to_list()
      assert length(rows) == 100
    end

    test "streams with custom chunk_size", %{instance: instance} do
      {:ok, lazy} =
        Cozonomono.query_lazy(
          instance,
          "?[id, name, score] := *users{id, name, score} :sort id"
        )

      rows = lazy |> LazyRows.to_stream(chunk_size: 10) |> Enum.to_list()
      assert length(rows) == 100
      assert Enum.at(rows, 0) == [1, "User_1", 1.5]
      assert Enum.at(rows, 99) == [100, "User_100", 150.0]
    end

    test "Stream.take stops early", %{instance: instance} do
      {:ok, lazy} =
        Cozonomono.query_lazy(
          instance,
          "?[id, name, score] := *users{id, name, score} :sort id"
        )

      rows = lazy |> LazyRows.to_stream(chunk_size: 5) |> Stream.take(3) |> Enum.to_list()
      assert length(rows) == 3
      assert Enum.at(rows, 0) == [1, "User_1", 1.5]
    end

    test "Stream.filter + Enum.to_list", %{instance: instance} do
      {:ok, lazy} =
        Cozonomono.query_lazy(instance, "?[id, name, score] := *users{id, name, score}")

      even_ids =
        lazy
        |> LazyRows.to_stream(chunk_size: 25)
        |> Stream.filter(fn [id | _] -> rem(id, 2) == 0 end)
        |> Enum.map(&hd/1)
        |> Enum.sort()

      assert even_ids == Enum.filter(1..100, &(rem(&1, 2) == 0))
    end

    test "empty result set", %{instance: instance} do
      {:ok, lazy} =
        Cozonomono.query_lazy(
          instance,
          "?[id, name, score] := *users{id, name, score}, id > 9999"
        )

      assert lazy |> LazyRows.to_stream() |> Enum.to_list() == []
    end

    test "Stream.map with side effects only processes chunks on demand", %{instance: instance} do
      {:ok, lazy} =
        Cozonomono.query_lazy(
          instance,
          "?[id, name, score] := *users{id, name, score} :sort id"
        )

      # Building the stream does no work
      stream = lazy |> LazyRows.to_stream(chunk_size: 10) |> Stream.map(&hd/1)

      # Only materializes when consumed
      first_five = stream |> Stream.take(5) |> Enum.to_list()
      assert first_five == [1, 2, 3, 4, 5]
    end
  end
end
