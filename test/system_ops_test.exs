defmodule Cozonomono.SystemOpsTest do
  use ExUnit.Case
  alias Cozonomono.NamedRows

  describe "list_relations/1" do
    test "returns empty list for fresh instance" do
      {:ok, instance} = Cozonomono.new()

      assert {:ok, %NamedRows{headers: headers, rows: []}} =
               Cozonomono.list_relations(instance)

      assert "name" in headers
      assert "arity" in headers
      assert "access_level" in headers
    end

    test "returns created relations" do
      {:ok, instance} = Cozonomono.new()
      {:ok, _} = Cozonomono.query(instance, ":create rel_a {id: Int}")
      {:ok, _} = Cozonomono.query(instance, ":create rel_b {id: Int => val: String}")

      assert {:ok, %NamedRows{rows: rows}} = Cozonomono.list_relations(instance)
      names = Enum.map(rows, &List.first/1)
      assert "rel_a" in names
      assert "rel_b" in names
    end
  end

  describe "list_columns/2" do
    test "returns column info for a relation" do
      {:ok, instance} = Cozonomono.new()
      {:ok, _} = Cozonomono.query(instance, ":create col_test {id: Int => name: String}")

      assert {:ok, %NamedRows{headers: headers, rows: rows}} =
               Cozonomono.list_columns(instance, "col_test")

      assert "column" in headers
      assert "is_key" in headers
      assert "type" in headers
      assert length(rows) == 2

      col_names = Enum.map(rows, &List.first/1)
      assert "id" in col_names
      assert "name" in col_names
    end

    test "returns error for non-existent relation" do
      {:ok, instance} = Cozonomono.new()
      assert {:error, _} = Cozonomono.list_columns(instance, "nonexistent")
    end
  end

  describe "list_indices/2" do
    test "returns empty list for relation with no indices" do
      {:ok, instance} = Cozonomono.new()
      {:ok, _} = Cozonomono.query(instance, ":create idx_test {id: Int => val: String}")

      assert {:ok, %NamedRows{rows: []}} = Cozonomono.list_indices(instance, "idx_test")
    end

    test "returns indices after creating one" do
      {:ok, instance} = Cozonomono.new()
      {:ok, _} = Cozonomono.query(instance, ":create idx_test2 {id: Int => val: String}")
      {:ok, _} = Cozonomono.query(instance, "::index create idx_test2:val_idx {val, id}")

      assert {:ok, %NamedRows{rows: rows}} = Cozonomono.list_indices(instance, "idx_test2")
      assert length(rows) == 1
    end
  end

  describe "remove_relation/2" do
    test "removes a single relation" do
      {:ok, instance} = Cozonomono.new()
      {:ok, _} = Cozonomono.query(instance, ":create to_remove {id: Int}")

      assert {:ok, _} = Cozonomono.remove_relation(instance, "to_remove")

      assert {:ok, %NamedRows{rows: []}} = Cozonomono.list_relations(instance)
    end

    test "removes multiple relations" do
      {:ok, instance} = Cozonomono.new()
      {:ok, _} = Cozonomono.query(instance, ":create rm_a {id: Int}")
      {:ok, _} = Cozonomono.query(instance, ":create rm_b {id: Int}")

      assert {:ok, _} = Cozonomono.remove_relation(instance, ["rm_a", "rm_b"])

      assert {:ok, %NamedRows{rows: []}} = Cozonomono.list_relations(instance)
    end

    test "returns error for non-existent relation" do
      {:ok, instance} = Cozonomono.new()
      assert {:error, _} = Cozonomono.remove_relation(instance, "nonexistent")
    end
  end

  describe "rename_relation/3" do
    test "renames a relation" do
      {:ok, instance} = Cozonomono.new()
      {:ok, _} = Cozonomono.query(instance, ":create old_name {id: Int}")

      assert {:ok, _} = Cozonomono.rename_relation(instance, "old_name", "new_name")

      assert {:ok, %NamedRows{rows: rows}} = Cozonomono.list_relations(instance)
      names = Enum.map(rows, &List.first/1)
      assert "new_name" in names
      refute "old_name" in names
    end
  end

  describe "explain/2" do
    test "returns a query plan" do
      {:ok, instance} = Cozonomono.new()
      {:ok, _} = Cozonomono.query(instance, ":create explain_test {id: Int => val: String}")

      assert {:ok, %NamedRows{headers: headers, rows: rows}} =
               Cozonomono.explain(instance, "?[id, val] := *explain_test{id, val}")

      assert "op" in headers
      assert length(rows) > 0
    end
  end

  describe "list_running/1" do
    test "returns running queries (empty when idle)" do
      {:ok, instance} = Cozonomono.new()

      assert {:ok, %NamedRows{headers: ["id", "started_at"], rows: []}} =
               Cozonomono.list_running(instance)
    end
  end

  describe "kill_running/2" do
    test "returns NOT_FOUND for invalid query id" do
      {:ok, instance} = Cozonomono.new()

      assert {:ok, %NamedRows{rows: [["NOT_FOUND"]]}} =
               Cozonomono.kill_running(instance, 999)
    end
  end

  describe "compact/1" do
    test "runs compaction without error" do
      {:ok, instance} = Cozonomono.new()
      assert {:ok, %NamedRows{rows: [["OK"]]}} = Cozonomono.compact(instance)
    end
  end
end
