defmodule Cozonomono.DataValueTest do
  use ExUnit.Case

  describe "null encoding" do
    test "null values are returned as nil atom, not string" do
      {:ok, instance} = Cozonomono.new()

      assert {:ok, %{"rows" => [[nil]], "headers" => ["_0"], "next" => nil}} =
               Cozonomono.query(instance, "?[] <- [[null]]")
    end

    test "null in mixed row" do
      {:ok, instance} = Cozonomono.new()

      assert {:ok, %{"rows" => [["hello", nil, 42]]}} =
               Cozonomono.query(instance, "?[] <- [['hello', null, 42]]")
    end
  end

  describe "null decoding (params)" do
    test "nil param is decoded as null" do
      {:ok, instance} = Cozonomono.new()

      assert {:ok, %{"rows" => [[nil]]}} =
               Cozonomono.query(instance, "?[] <- [[$val]]", params: %{"val" => nil})
    end
  end

  describe "boolean encoding" do
    test "true and false are returned as atoms" do
      {:ok, instance} = Cozonomono.new()

      assert {:ok, %{"rows" => [[true, false]]}} =
               Cozonomono.query(instance, "?[] <- [[true, false]]")
    end
  end

  describe "boolean decoding (params)" do
    test "boolean params round-trip" do
      {:ok, instance} = Cozonomono.new()

      assert {:ok, %{"rows" => [[true, false]]}} =
               Cozonomono.query(instance, "?[] <- [[$a, $b]]",
                 params: %{"a" => true, "b" => false}
               )
    end
  end

  describe "numeric encoding" do
    test "integers" do
      {:ok, instance} = Cozonomono.new()

      assert {:ok, %{"rows" => [[0, 42, -100]]}} =
               Cozonomono.query(instance, "?[] <- [[0, 42, -100]]")
    end

    test "floats" do
      {:ok, instance} = Cozonomono.new()

      assert {:ok, %{"rows" => [[3.14, -2.718]]}} =
               Cozonomono.query(instance, "?[] <- [[3.14, -2.718]]")
    end
  end

  describe "string encoding" do
    test "basic strings" do
      {:ok, instance} = Cozonomono.new()

      assert {:ok, %{"rows" => [["hello", ""]]}} =
               Cozonomono.query(instance, "?[] <- [['hello', '']]")
    end

    test "unicode strings" do
      {:ok, instance} = Cozonomono.new()

      assert {:ok, %{"rows" => [["héllo wörld 🚀"]]}} =
               Cozonomono.query(instance, "?[] <- [['héllo wörld 🚀']]")
    end
  end

  describe "string decoding (params)" do
    test "string param" do
      {:ok, instance} = Cozonomono.new()

      assert {:ok, %{"rows" => [["test_value"]]}} =
               Cozonomono.query(instance, "?[] <- [[$s]]", params: %{"s" => "test_value"})
    end
  end

  describe "list encoding" do
    test "nested lists" do
      {:ok, instance} = Cozonomono.new()

      assert {:ok, %{"rows" => [[[1, [2, 3]]]]}} =
               Cozonomono.query(instance, "?[] <- [[[1, [2, 3]]]]")
    end

    test "list with mixed types" do
      {:ok, instance} = Cozonomono.new()

      assert {:ok, %{"rows" => [[["hello", 42, true]]]}} =
               Cozonomono.query(instance, "?[] <- [[['hello', 42, true]]]")
    end
  end

  describe "list decoding (params)" do
    test "list param" do
      {:ok, instance} = Cozonomono.new()

      assert {:ok, %{"rows" => [[[1, 2, 3]]]}} =
               Cozonomono.query(instance, "?[] <- [[$l]]", params: %{"l" => [1, 2, 3]})
    end
  end

  describe "uuid decoding (params)" do
    test "UUID string param is decoded as UUID DataValue" do
      {:ok, instance} = Cozonomono.new()

      uuid_str = "550e8400-e29b-41d4-a716-446655440000"

      # When we pass a UUID string as a param, CozoDB should treat it as a UUID.
      # CozoDB returns UUIDs as strings, so we verify it round-trips.
      assert {:ok, %{"rows" => [[^uuid_str]]}} =
               Cozonomono.query(instance, "?[] <- [[$id]]", params: %{"id" => uuid_str})
    end

    test "non-UUID string param stays as string" do
      {:ok, instance} = Cozonomono.new()

      assert {:ok, %{"rows" => [["not-a-uuid"]]}} =
               Cozonomono.query(instance, "?[] <- [[$s]]", params: %{"s" => "not-a-uuid"})
    end
  end

  describe "json decoding (params)" do
    test "map param is decoded as JSON DataValue" do
      {:ok, instance} = Cozonomono.new()

      json_param = %{"name" => "Alice", "age" => 30}

      # CozoDB stores JSON and returns it — we should get a map back
      assert {:ok, %{"rows" => [[result]]}} =
               Cozonomono.query(instance, "?[] <- [[$data]]", params: %{"data" => json_param})

      assert is_map(result)
      assert result["name"] == "Alice"
      assert result["age"] == 30
    end

    test "nested map param" do
      {:ok, instance} = Cozonomono.new()

      json_param = %{"user" => %{"name" => "Bob", "scores" => [1, 2, 3]}}

      assert {:ok, %{"rows" => [[result]]}} =
               Cozonomono.query(instance, "?[] <- [[$data]]", params: %{"data" => json_param})

      assert result["user"]["name"] == "Bob"
      assert result["user"]["scores"] == [1, 2, 3]
    end
  end

  describe "json encoding" do
    test "json values are returned as native Elixir maps" do
      {:ok, instance} = Cozonomono.new()

      # Use json() function to create a JSON value in CozoScript
      assert {:ok, %{"rows" => [[result]]}} =
               Cozonomono.query(instance, "?[] <- [[$j]]", params: %{"j" => %{"key" => "value"}})

      assert is_map(result)
      assert result["key"] == "value"
    end
  end

  describe "stored relations with diverse types" do
    test "round-trip through stored relation" do
      {:ok, instance} = Cozonomono.new()

      # Create a relation
      assert {:ok, _} =
               Cozonomono.query(
                 instance,
                 ":create test {id: Int => name: String, score: Float, active: Bool}"
               )

      # Insert data
      assert {:ok, _} =
               Cozonomono.query(
                 instance,
                 "?[id, name, score, active] <- [[1, 'Alice', 95.5, true], [2, 'Bob', 87.0, false]] :put test {id => name, score, active}"
               )

      # Query it back
      assert {:ok, %{"rows" => rows}} =
               Cozonomono.query(
                 instance,
                 "?[id, name, score, active] := *test{id, name, score, active}"
               )

      assert length(rows) == 2
      alice = Enum.find(rows, fn [id | _] -> id == 1 end)
      assert alice == [1, "Alice", 95.5, true]
    end
  end

  describe "multi-statement results (next chain)" do
    test "imperative block returns last statement result" do
      {:ok, instance} = Cozonomono.new()

      assert {:ok, _} =
               Cozonomono.query(instance, ":create chain_test {id: Int => val: String}")

      # CozoDB imperative blocks return the last statement's result
      result =
        Cozonomono.query(instance, """
        {?[id, val] <- [[1, 'hello']] :put chain_test {id => val}}
        {?[id, val] := *chain_test{id, val}}
        """)

      assert {:ok, %{"headers" => ["id", "val"], "rows" => [[1, "hello"]], "next" => nil}} =
               result
    end
  end
end
