# Indexes and Search

Official docs: [Proximity searches](https://docs.cozodb.org/en/latest/vector.html), [Stored relation indices](https://docs.cozodb.org/en/latest/stored.html#indices)

See also:

- [Stored Relations and Mutations](stored-relations-and-mutations.md)
- [Graph Algorithms and Fixed Rules](graph-algorithms-and-fixed-rules.md)

## Standard indexes

```elixir
{:ok, _} =
  Cozonomono.query(
    db,
    ":create users {id: Int => name: String, email: String}"
  )

{:ok, _} = Cozonomono.create_index(db, "users", "users_by_email", ["email"])
```

List them with:

```elixir
{:ok, idxs} = Cozonomono.list_indices(db, "users")
```

## HNSW vector search

Create a relation with vector data:

```elixir
{:ok, _} =
  Cozonomono.query(
    db,
    ":create docs {id: Int => title: String, embedding: <F32; 3>}"
  )

{:ok, _} =
  Cozonomono.query(
    db,
    """
    ?[id, title, embedding] <- [
      [1, 'cozo intro', [1.0, 0.0, 0.0]],
      [2, 'cozo search', [0.9, 0.1, 0.0]],
      [3, 'rust nif', [0.0, 1.0, 0.0]]
    ]
    :put docs {id => title, embedding}
    """
  )

{:ok, _} =
  Cozonomono.create_hnsw_index(
    db,
    "docs",
    "docs_hnsw",
    "dim: 3, dtype: F32, fields: [embedding], distance: Cosine, ef_construction: 50, m: 16"
  )
```

Search with raw CozoScript:

```elixir
{:ok, result} =
  Cozonomono.query(
    db,
    """
    ?[distance, id, title] := ~docs:docs_hnsw {
      id,
      title |
      query: vec([1.0, 0.0, 0.0]),
      k: 2,
      ef: 20,
      bind_distance: distance
    }
    :sort distance
    """
  )
```

## Full-text search

```elixir
{:ok, _} =
  Cozonomono.query(
    db,
    ":create articles {id: Int => content: String}"
  )

{:ok, _} =
  Cozonomono.query(
    db,
    """
    ?[id, content] <- [
      [1, 'cozo is a transactional graph database'],
      [2, 'cozonomono wraps cozo for elixir'],
      [3, 'rustler powers the nif boundary']
    ]
    :put articles {id => content}
    """
  )

{:ok, _} =
  Cozonomono.create_fts_index(
    db,
    "articles",
    "articles_fts",
    "extractor: content, tokenizer: Simple, filters: []"
  )
```

Query the index:

```elixir
{:ok, result} =
  Cozonomono.query(
    db,
    """
    ?[score, id, content] := ~articles:articles_fts {
      id,
      content |
      query: $query,
      k: 10,
      score_kind: 'tf_idf',
      bind_score: score
    }
    :sort -score
    """,
    params: %{"query" => "cozo AND elixir"}
  )
```

## MinHash LSH

```elixir
{:ok, _} =
  Cozonomono.query(
    db,
    ":create snippets {id: Int => content: String}"
  )

{:ok, _} =
  Cozonomono.query(
    db,
    """
    ?[id, content] <- [
      [1, 'the quick brown fox jumps over the lazy dog'],
      [2, 'the quick brown fox jumped over a lazy dog'],
      [3, 'vector search with hnsw']
    ]
    :put snippets {id => content}
    """
  )

{:ok, _} =
  Cozonomono.create_lsh_index(
    db,
    "snippets",
    "snippets_lsh",
    "extractor: content, tokenizer: Simple, filters: [], n_gram: 3, n_perm: 200"
  )
```

Search near-duplicates:

```elixir
{:ok, result} =
  Cozonomono.query(
    db,
    """
    ?[id, content] := ~snippets:snippets_lsh {
      id,
      content |
      query: $query,
      k: 2
    }
    """,
    params: %{"query" => "the quick brown fox jumps over the lazy dog"}
  )
```

## Scope of the local docs

Local docs should show:

- how to create each index through Cozonomono helpers
- how to query each index from Elixir
- the minimum set of options people need to start

Link out to the official proximity chapter for the full option matrix and tokenizer/filter details.
