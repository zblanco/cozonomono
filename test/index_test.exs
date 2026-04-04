defmodule IndexTest do
  use ExUnit.Case
  alias Cozonomono.NamedRows

  setup do
    {:ok, instance} = Cozonomono.new()
    %{instance: instance}
  end

  describe "standard indices" do
    setup %{instance: instance} do
      Cozonomono.query(instance, ":create users {id: Int => name: String, email: String}")
      :ok
    end

    test "create and list index", %{instance: instance} do
      assert {:ok, %NamedRows{}} =
               Cozonomono.create_index(instance, "users", "users_by_name", ["name"])

      {:ok, %NamedRows{rows: rows}} = Cozonomono.list_indices(instance, "users")
      index_names = Enum.map(rows, &Enum.at(&1, 0))
      assert "users_by_name" in index_names
    end

    test "create multi-column index", %{instance: instance} do
      assert {:ok, %NamedRows{}} =
               Cozonomono.create_index(instance, "users", "users_by_name_email", [
                 "name",
                 "email"
               ])

      {:ok, %NamedRows{rows: rows}} = Cozonomono.list_indices(instance, "users")
      index_names = Enum.map(rows, &Enum.at(&1, 0))
      assert "users_by_name_email" in index_names
    end

    test "drop index", %{instance: instance} do
      Cozonomono.create_index(instance, "users", "users_by_name", ["name"])

      assert {:ok, %NamedRows{}} =
               Cozonomono.drop_index(instance, "users", "users_by_name")

      {:ok, %NamedRows{rows: rows}} = Cozonomono.list_indices(instance, "users")
      index_names = Enum.map(rows, &Enum.at(&1, 0))
      refute "users_by_name" in index_names
    end

    test "drop non-existent index returns error", %{instance: instance} do
      assert {:error, _} = Cozonomono.drop_index(instance, "users", "nope")
    end
  end

  describe "FTS indices" do
    setup %{instance: instance} do
      Cozonomono.query(instance, ":create docs {id: Int => content: String}")
      :ok
    end

    test "create and list FTS index", %{instance: instance} do
      assert {:ok, %NamedRows{}} =
               Cozonomono.create_fts_index(
                 instance,
                 "docs",
                 "docs_fts",
                 "extractor: content, tokenizer: Simple"
               )

      {:ok, %NamedRows{rows: rows}} = Cozonomono.list_indices(instance, "docs")
      index_names = Enum.map(rows, &Enum.at(&1, 0))
      assert "docs_fts" in index_names
    end

    test "drop FTS index", %{instance: instance} do
      Cozonomono.create_fts_index(
        instance,
        "docs",
        "docs_fts",
        "extractor: content, tokenizer: Simple"
      )

      assert {:ok, %NamedRows{}} = Cozonomono.drop_index(instance, "docs", "docs_fts")

      {:ok, %NamedRows{rows: rows}} = Cozonomono.list_indices(instance, "docs")
      index_names = Enum.map(rows, &Enum.at(&1, 0))
      refute "docs_fts" in index_names
    end
  end

  describe "HNSW indices" do
    setup %{instance: instance} do
      Cozonomono.query(
        instance,
        ":create vectors {id: Int => embedding: <F32; 3>}"
      )

      :ok
    end

    test "create HNSW index", %{instance: instance} do
      assert {:ok, %NamedRows{}} =
               Cozonomono.create_hnsw_index(
                 instance,
                 "vectors",
                 "vectors_hnsw",
                 "dim: 3, dtype: F32, fields: [embedding], distance: L2, ef_construction: 50, m_neighbours: 16"
               )

      {:ok, %NamedRows{rows: rows}} = Cozonomono.list_indices(instance, "vectors")
      index_names = Enum.map(rows, &Enum.at(&1, 0))
      assert "vectors_hnsw" in index_names
    end
  end

  describe "LSH indices" do
    setup %{instance: instance} do
      Cozonomono.query(instance, ":create docs {id: Int => content: String}")
      :ok
    end

    test "create LSH index", %{instance: instance} do
      assert {:ok, %NamedRows{}} =
               Cozonomono.create_lsh_index(
                 instance,
                 "docs",
                 "docs_lsh",
                 "extractor: content, tokenizer: Simple, n_gram: 3, n_perm: 200"
               )

      {:ok, %NamedRows{rows: rows}} = Cozonomono.list_indices(instance, "docs")
      index_names = Enum.map(rows, &Enum.at(&1, 0))
      assert "docs_lsh" in index_names
    end
  end
end
