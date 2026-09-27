# Graph Algorithms and Fixed Rules

Official docs:

- [Utilities and algorithms](https://docs.cozodb.org/en/latest/algorithms.html)
- [Queries: fixed rules](https://docs.cozodb.org/en/latest/queries.html#fixed-rules)

See also:

- [Indexes and Search](indexes-and-search.md)
- [Integration APIs](integration-apis.md)

## Built-in graph algorithms still use CozoScript

Create a graph relation:

```elixir
{:ok, _} =
  Cozonomono.query(
    db,
    ":create routes {from: String, to: String => distance: Float}"
  )

{:ok, _} =
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
```

Run Dijkstra through a fixed rule:

```elixir
{:ok, result} =
  Cozonomono.query(
    db,
    """
    starting[] <- [['DEN']]
    goal[] <- [['SEA']]
    ?[starting, goal, distance, path] <~
      ShortestPathDijkstra(*routes[], starting[], goal[])
    """
  )
```

PageRank looks similar:

```elixir
{:ok, result} =
  Cozonomono.query(
    db,
    """
    ?[node, score] <~ PageRank(*routes[from, to, distance], theta: 0.85)
    :sort -score
    """
  )
```

## Keep the local algorithm docs selective

Mirror a few representative workflows:

- shortest paths
- PageRank or another centrality example
- one utility example if needed

Do not try to restate the full algorithm catalog in ExDoc. Link to the official algorithms chapter for the rest.

## Custom fixed rules from Elixir

Cozonomono adds a wrapper for hosting your own fixed rule logic in Elixir.

```elixir
{:ok, bridge} = Cozonomono.register_fixed_rule(db, "EchoOnce", 1)

task =
  Task.async(fn ->
    Cozonomono.query(db, "?[value] <~ EchoOnce()")
  end)

receive do
  {:cozo_fixed_rule, request_id, _inputs, _options} ->
    result = %Cozonomono.NamedRows{headers: ["value"], rows: [[42]]}
    :ok = Cozonomono.respond_fixed_rule(bridge, request_id, result)
end

{:ok, rows} = Task.await(task, 5_000)
```

Use this when the built-in fixed rules are not enough but you still want Cozo to call back into Elixir during query execution.
