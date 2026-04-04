defmodule Cozonomono.DocumentationGuidesTest do
  use ExUnit.Case

  alias Cozonomono.NamedRows

  describe "stored-relations-and-mutations guide" do
    test "covers verified mutation forms" do
      {:ok, db} = Cozonomono.new()

      assert {:ok, %NamedRows{rows: [["OK"]]}} =
               Cozonomono.query(
                 db,
                 ":create users {id: Int => name: String, score: Float default 0.0}"
               )

      assert {:ok, %NamedRows{rows: [["OK"]]}} =
               Cozonomono.query(
                 db,
                 "?[id, name, score] <- [[1, 'Alice', 9.5], [2, 'Bob', 7.0]] :put users {id => name, score}"
               )

      assert {:ok, %NamedRows{headers: ["_kind", "id", "name", "score"]}} =
               Cozonomono.query(
                 db,
                 "?[id, name] <- [[3, 'Cara']] :put users {id => name} :returning"
               )

      assert {:ok, %NamedRows{rows: [["OK"]]}} =
               Cozonomono.query(
                 db,
                 "?[id, score] <- [[1, 10.0]] :update users {id => score}"
               )

      assert {:ok, %NamedRows{rows: [["OK"]]}} =
               Cozonomono.query(
                 db,
                 "?[id] <- [[2]] :delete users {id}"
               )

      assert {:ok, %NamedRows{rows: [["OK"]]}} =
               Cozonomono.query(
                 db,
                 "?[id, name, score] <- [[4, 'Drew', 8.0]] :replace users {id => name, score}"
               )

      assert {:ok, %NamedRows{rows: [[4, "Drew", 8.0]]}} =
               Cozonomono.query(
                 db,
                 "?[id, name, score] := *users{id, name, score} :sort id"
               )
    end
  end

  describe "time-travel guide" do
    test "covers validity values and historical reads" do
      {:ok, db} = Cozonomono.new()

      assert {:ok, %NamedRows{rows: [["OK"]]}} =
               Cozonomono.query(
                 db,
                 ":create status {user: String, valid_at: Validity => mood: String}"
               )

      assert {:ok, %NamedRows{rows: [["OK"]]}} =
               Cozonomono.query(
                 db,
                 """
                 ?[user, valid_at, mood] <- [
                   ['alice', [10, true], 'happy'],
                   ['alice', [20, true], 'focused'],
                   ['alice', [30, false], '']
                 ]
                 :put status {user, valid_at => mood}
                 """
               )

      assert {:ok, %NamedRows{rows: [["happy"]]}} =
               Cozonomono.query(
                 db,
                 "?[mood] := *status{user: 'alice', valid_at, mood @ 15}"
               )

      assert {:ok, %NamedRows{rows: [["focused"]]}} =
               Cozonomono.query(
                 db,
                 "?[mood] := *status{user: 'alice', valid_at, mood @ 25}"
               )

      assert {:ok, %NamedRows{rows: rows}} =
               Cozonomono.query(
                 db,
                 "?[user, valid_at, mood] := *status{user, valid_at, mood} :sort valid_at"
               )

      assert Enum.at(rows, 0) == ["alice", {:validity, 30, false}, ""]
      assert Enum.at(rows, 1) == ["alice", {:validity, 20, true}, "focused"]
      assert Enum.at(rows, 2) == ["alice", {:validity, 10, true}, "happy"]
    end
  end

  describe "indexes-and-search guide" do
    test "covers HNSW search" do
      {:ok, db} = Cozonomono.new()

      assert {:ok, %NamedRows{rows: [["OK"]]}} =
               Cozonomono.query(
                 db,
                 ":create docs {id: Int => embedding: <F32; 3>, title: String}"
               )

      assert {:ok, %NamedRows{rows: [["OK"]]}} =
               Cozonomono.query(
                 db,
                 """
                 ?[id, embedding, title] <- [
                   [1, [1.0, 0.0, 0.0], 'alpha'],
                   [2, [0.0, 1.0, 0.0], 'beta'],
                   [3, [0.9, 0.1, 0.0], 'alpha_near']
                 ]
                 :put docs {id => embedding, title}
                 """
               )

      assert {:ok, %NamedRows{rows: [["OK"]]}} =
               Cozonomono.create_hnsw_index(
                 db,
                 "docs",
                 "docs_vec",
                 "dim: 3, dtype: F32, fields: [embedding], distance: Cosine, ef_construction: 50, m_neighbours: 16"
               )

      assert {:ok, %NamedRows{rows: rows}} =
               Cozonomono.query(
                 db,
                 """
                 ?[dist, id, title] := ~docs:docs_vec{id, title |
                   query: vec([1.0, 0.0, 0.0]),
                   k: 2,
                   ef: 20,
                   bind_distance: dist
                 }
                 :sort dist
                 """
               )

      assert Enum.at(rows, 0) == [0.0, 1, "alpha"]
      [distance, 3, "alpha_near"] = Enum.at(rows, 1)
      assert is_float(distance)
      assert distance > 0.0
    end

    test "covers FTS and LSH search" do
      {:ok, db} = Cozonomono.new()

      assert {:ok, %NamedRows{rows: [["OK"]]}} =
               Cozonomono.query(
                 db,
                 ":create pages {id: Int => content: String}"
               )

      assert {:ok, %NamedRows{rows: [["OK"]]}} =
               Cozonomono.query(
                 db,
                 """
                 ?[id, content] <- [
                   [1, 'hello world from cozo'],
                   [2, 'vector search and graph data'],
                   [3, 'hello again world']
                 ]
                 :put pages {id => content}
                 """
               )

      assert {:ok, %NamedRows{rows: [["OK"]]}} =
               Cozonomono.create_fts_index(
                 db,
                 "pages",
                 "pages_fts",
                 "extractor: content, tokenizer: Simple, filters: [Lowercase]"
               )

      assert {:ok, %NamedRows{rows: rows}} =
               Cozonomono.query(
                 db,
                 """
                 ?[score, id, content] := ~pages:pages_fts{id, content |
                   query: 'hello AND world',
                   k: 10,
                   score_kind: 'tf_idf',
                   bind_score: score
                 }
                 :sort -score
                 """
               )

      assert Enum.map(rows, &Enum.at(&1, 1)) == [1, 3]

      assert {:ok, %NamedRows{rows: [["OK"]]}} =
               Cozonomono.query(
                 db,
                 """
                 ?[id, content] <- [
                   [1, 'hello world from cozo'],
                   [2, 'hello world from cozo!'],
                   [3, 'entirely different text']
                 ]
                 :put pages {id => content}
                 """
               )

      assert {:ok, %NamedRows{rows: [["OK"]]}} =
               Cozonomono.create_lsh_index(
                 db,
                 "pages",
                 "pages_lsh",
                 "extractor: content, tokenizer: Simple, n_gram: 3, n_perm: 200"
               )

      assert {:ok,
              %NamedRows{rows: [[1, "hello world from cozo"], [2, "hello world from cozo!"]]}} =
               Cozonomono.query(
                 db,
                 "?[id, content] := ~pages:pages_lsh{id, content | query: 'hello world from cozo', k: 5}"
               )
    end
  end

  describe "integration-apis guide" do
    test "covers import_relations removal semantics" do
      {:ok, db} = Cozonomono.new()

      assert {:ok, %NamedRows{rows: [["OK"]]}} =
               Cozonomono.query(
                 db,
                 ":create users {id: Int => name: String}"
               )

      assert :ok =
               Cozonomono.import_relations(db, %{
                 "users" => %NamedRows{
                   headers: ["id", "name"],
                   rows: [[1, "Alice"], [2, "Bob"]]
                 }
               })

      assert :ok =
               Cozonomono.import_relations(db, %{
                 "-users" => %NamedRows{
                   headers: ["id"],
                   rows: [[2]]
                 }
               })

      assert {:ok, %NamedRows{rows: [[1, "Alice"]]}} =
               Cozonomono.query(
                 db,
                 "?[id, name] := *users{id, name} :sort id"
               )
    end
  end

  describe "graph-algorithms-and-fixed-rules guide" do
    test "covers Dijkstra and PageRank examples" do
      {:ok, db} = Cozonomono.new()

      assert {:ok, %NamedRows{rows: [["OK"]]}} =
               Cozonomono.query(
                 db,
                 ":create routes {from: String, to: String => distance: Float}"
               )

      assert {:ok, %NamedRows{rows: [["OK"]]}} =
               Cozonomono.query(
                 db,
                 """
                 ?[from, to, distance] <- [
                   ['DEN', 'SLC', 1.0],
                   ['SLC', 'SEA', 1.0],
                   ['DEN', 'PHX', 2.0],
                   ['PHX', 'SEA', 1.0]
                 ]
                 :put routes {from, to => distance}
                 """
               )

      assert {:ok, %NamedRows{rows: [["DEN", "SEA", 2.0, ["DEN", "SLC", "SEA"]]]}} =
               Cozonomono.query(
                 db,
                 """
                 starting[] <- [['DEN']]
                 goal[] <- [['SEA']]
                 ?[starting, goal, distance, path] <~ ShortestPathDijkstra(*routes[], starting[], goal[])
                 """
               )

      assert {:ok, %NamedRows{rows: pagerank_rows}} =
               Cozonomono.query(
                 db,
                 """
                 ?[node, score] <~ PageRank(*routes[from, to, distance], theta: 0.85)
                 :sort -score
                 """
               )

      ["SEA", score] = Enum.at(pagerank_rows, 0)
      assert_in_delta score, 0.12834373116493225, 1.0e-12
    end
  end
end
