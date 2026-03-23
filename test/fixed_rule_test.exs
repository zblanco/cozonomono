defmodule FixedRuleTest do
  use ExUnit.Case
  alias Cozonomono.NamedRows

  setup do
    {:ok, instance} = Cozonomono.new()
    %{instance: instance}
  end

  test "register and invoke a simple fixed rule", %{instance: instance} do
    {:ok, bridge} = Cozonomono.register_fixed_rule(instance, "MyConst", 2)

    # Run query in a task because it blocks until the rule responds
    task =
      Task.async(fn ->
        Cozonomono.query(instance, "?[a, b] <~ MyConst()")
      end)

    # Handle the rule invocation
    assert_receive {:cozo_fixed_rule, request_id, inputs, options}, 2_000
    assert is_integer(request_id)
    assert is_list(inputs)
    assert is_map(options)

    result = %NamedRows{headers: ["a", "b"], rows: [[10, 20], [30, 40]]}
    assert :ok = Cozonomono.respond_fixed_rule(bridge, request_id, result)

    # Get the query result
    assert {:ok, %NamedRows{rows: rows}} = Task.await(task, 5_000)
    assert rows == [[10, 20], [30, 40]]
  end

  test "fixed rule receives input relations", %{instance: instance} do
    Cozonomono.query(instance, ":create items {id: Int => val: String}")
    Cozonomono.query(instance, "?[id, val] <- [[1, 'a'], [2, 'b']] :put items {id => val}")

    {:ok, bridge} = Cozonomono.register_fixed_rule(instance, "Echo", 2)

    task =
      Task.async(fn ->
        Cozonomono.query(
          instance,
          "in_data[id, val] := *items[id, val]; ?[a, b] <~ Echo(in_data[])"
        )
      end)

    assert_receive {:cozo_fixed_rule, request_id, inputs, _options}, 2_000

    # inputs should contain the items relation data
    assert [%NamedRows{rows: input_rows}] = inputs
    assert length(input_rows) == 2

    # Echo back the input as result
    result = %NamedRows{headers: ["a", "b"], rows: input_rows}
    Cozonomono.respond_fixed_rule(bridge, request_id, result)

    assert {:ok, %NamedRows{rows: rows}} = Task.await(task, 5_000)
    assert length(rows) == 2
  end

  test "fixed rule with options", %{instance: instance} do
    {:ok, bridge} = Cozonomono.register_fixed_rule(instance, "WithOpts", 1)

    task =
      Task.async(fn ->
        Cozonomono.query(instance, "?[a] <~ WithOpts(multiplier: 3)")
      end)

    assert_receive {:cozo_fixed_rule, request_id, _inputs, options}, 2_000
    assert Map.has_key?(options, "multiplier")

    result = %NamedRows{headers: ["a"], rows: [[42]]}
    Cozonomono.respond_fixed_rule(bridge, request_id, result)

    assert {:ok, %NamedRows{rows: [[42]]}} = Task.await(task, 5_000)
  end

  test "fixed rule invoked multiple times", %{instance: instance} do
    {:ok, bridge} = Cozonomono.register_fixed_rule(instance, "Counter", 1)

    task =
      Task.async(fn ->
        # Two separate queries
        {:ok, r1} = Cozonomono.query(instance, "?[a] <~ Counter()")
        {:ok, r2} = Cozonomono.query(instance, "?[a] <~ Counter()")
        {r1, r2}
      end)

    # Handle first invocation
    assert_receive {:cozo_fixed_rule, req1, _, _}, 2_000
    Cozonomono.respond_fixed_rule(bridge, req1, %NamedRows{headers: ["a"], rows: [[1]]})

    # Handle second invocation
    assert_receive {:cozo_fixed_rule, req2, _, _}, 2_000
    Cozonomono.respond_fixed_rule(bridge, req2, %NamedRows{headers: ["a"], rows: [[2]]})

    {r1, r2} = Task.await(task, 5_000)
    assert r1.rows == [[1]]
    assert r2.rows == [[2]]
  end

  test "unregister_fixed_rule removes the rule", %{instance: instance} do
    {:ok, _bridge} = Cozonomono.register_fixed_rule(instance, "Temp", 1)

    assert {:ok, true} = Cozonomono.unregister_fixed_rule(instance, "Temp")
    assert {:ok, false} = Cozonomono.unregister_fixed_rule(instance, "Temp")

    # Querying removed rule should error
    assert {:error, _} = Cozonomono.query(instance, "?[a] <~ Temp()")
  end
end
