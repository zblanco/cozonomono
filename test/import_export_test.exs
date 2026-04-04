defmodule Cozonomono.ImportExportTest do
  use ExUnit.Case
  alias Cozonomono.NamedRows

  describe "export_relations/2" do
    test "exports a single relation" do
      {:ok, instance} = Cozonomono.new()

      {:ok, _} =
        Cozonomono.query(instance, ":create users {id: Int => name: String, score: Float}")

      {:ok, _} =
        Cozonomono.query(
          instance,
          "?[id, name, score] <- [[1, 'Alice', 95.5], [2, 'Bob', 87.0]] :put users {id => name, score}"
        )

      assert {:ok, %{"users" => %NamedRows{headers: headers, rows: rows}}} =
               Cozonomono.export_relations(instance, ["users"])

      assert "id" in headers
      assert "name" in headers
      assert "score" in headers
      assert length(rows) == 2
    end

    test "exports multiple relations" do
      {:ok, instance} = Cozonomono.new()

      {:ok, _} = Cozonomono.query(instance, ":create rel_a {id: Int => val: String}")
      {:ok, _} = Cozonomono.query(instance, ":create rel_b {id: Int => flag: Bool}")

      {:ok, _} =
        Cozonomono.query(
          instance,
          "?[id, val] <- [[1, 'x'], [2, 'y']] :put rel_a {id => val}"
        )

      {:ok, _} =
        Cozonomono.query(
          instance,
          "?[id, flag] <- [[1, true], [2, false]] :put rel_b {id => flag}"
        )

      assert {:ok, %{"rel_a" => %NamedRows{}, "rel_b" => %NamedRows{}}} =
               Cozonomono.export_relations(instance, ["rel_a", "rel_b"])
    end

    test "exports an empty relation" do
      {:ok, instance} = Cozonomono.new()
      {:ok, _} = Cozonomono.query(instance, ":create empty_rel {id: Int => val: String}")

      assert {:ok, %{"empty_rel" => %NamedRows{rows: []}}} =
               Cozonomono.export_relations(instance, ["empty_rel"])
    end

    test "returns error for non-existent relation" do
      {:ok, instance} = Cozonomono.new()

      assert {:error, _} = Cozonomono.export_relations(instance, ["nonexistent"])
    end
  end

  describe "import_relations/2" do
    test "imports data into an existing relation" do
      {:ok, instance} = Cozonomono.new()

      {:ok, _} =
        Cozonomono.query(instance, ":create imports {id: Int => name: String}")

      assert :ok =
               Cozonomono.import_relations(instance, %{
                 "imports" => %NamedRows{
                   headers: ["id", "name"],
                   rows: [[1, "Alice"], [2, "Bob"]]
                 }
               })

      assert {:ok, %NamedRows{rows: rows}} =
               Cozonomono.query(instance, "?[id, name] := *imports{id, name}")

      assert length(rows) == 2
      alice = Enum.find(rows, fn [id | _] -> id == 1 end)
      assert alice == [1, "Alice"]
    end

    test "imports into multiple relations at once" do
      {:ok, instance} = Cozonomono.new()

      {:ok, _} = Cozonomono.query(instance, ":create imp_a {id: Int => val: String}")
      {:ok, _} = Cozonomono.query(instance, ":create imp_b {id: Int => flag: Bool}")

      assert :ok =
               Cozonomono.import_relations(instance, %{
                 "imp_a" => %NamedRows{headers: ["id", "val"], rows: [[1, "hello"]]},
                 "imp_b" => %NamedRows{headers: ["id", "flag"], rows: [[1, true]]}
               })

      assert {:ok, %NamedRows{rows: [[1, "hello"]]}} =
               Cozonomono.query(instance, "?[id, val] := *imp_a{id, val}")

      assert {:ok, %NamedRows{rows: [[1, true]]}} =
               Cozonomono.query(instance, "?[id, flag] := *imp_b{id, flag}")
    end

    test "returns error for non-existent relation" do
      {:ok, instance} = Cozonomono.new()

      assert {:error, _} =
               Cozonomono.import_relations(instance, %{
                 "no_such_rel" => %NamedRows{headers: ["id"], rows: [[1]]}
               })
    end
  end

  describe "export then import round-trip" do
    test "data survives export → import to a new instance" do
      {:ok, src} = Cozonomono.new()

      {:ok, _} =
        Cozonomono.query(src, ":create roundtrip {id: Int => name: String, active: Bool}")

      {:ok, _} =
        Cozonomono.query(
          src,
          "?[id, name, active] <- [[1, 'Alice', true], [2, 'Bob', false]] :put roundtrip {id => name, active}"
        )

      {:ok, exported} = Cozonomono.export_relations(src, ["roundtrip"])

      # Import into a fresh instance
      {:ok, dst} = Cozonomono.new()

      {:ok, _} =
        Cozonomono.query(dst, ":create roundtrip {id: Int => name: String, active: Bool}")

      assert :ok = Cozonomono.import_relations(dst, exported)

      assert {:ok, %NamedRows{rows: rows}} =
               Cozonomono.query(dst, "?[id, name, active] := *roundtrip{id, name, active}")

      assert length(rows) == 2
      alice = Enum.find(rows, fn [id | _] -> id == 1 end)
      assert alice == [1, "Alice", true]
      bob = Enum.find(rows, fn [id | _] -> id == 2 end)
      assert bob == [2, "Bob", false]
    end
  end
end
