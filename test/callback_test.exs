defmodule CallbackTest do
  use ExUnit.Case
  alias Cozonomono.NamedRows

  setup do
    {:ok, instance} = Cozonomono.new()

    Cozonomono.query(instance, """
    :create users {id: Int => name: String}
    """)

    %{instance: instance}
  end

  test "register_callback returns an id", %{instance: instance} do
    assert {:ok, id} = Cozonomono.register_callback(instance, "users")
    assert is_integer(id)
  end

  test "callback fires on put", %{instance: instance} do
    {:ok, _cb_id} = Cozonomono.register_callback(instance, "users")

    Cozonomono.query(instance, "?[id, name] <- [[1, 'Alice']] :put users {id => name}")

    assert_receive {:cozo_callback, :put, %NamedRows{} = new_rows, %NamedRows{} = old_rows},
                   1_000

    assert new_rows.headers == ["id", "name"]
    assert new_rows.rows == [[1, "Alice"]]
    assert old_rows.rows == []
  end

  test "callback fires on rm", %{instance: instance} do
    Cozonomono.query(instance, "?[id, name] <- [[1, 'Alice']] :put users {id => name}")

    {:ok, _cb_id} = Cozonomono.register_callback(instance, "users")

    Cozonomono.query(instance, "?[id, name] <- [[1, 'Alice']] :rm users {id => name}")

    assert_receive {:cozo_callback, :rm, %NamedRows{} = _new_rows, %NamedRows{} = _old_rows},
                   1_000
  end

  test "callback fires multiple times", %{instance: instance} do
    {:ok, _cb_id} = Cozonomono.register_callback(instance, "users")

    Cozonomono.query(instance, "?[id, name] <- [[1, 'Alice']] :put users {id => name}")
    Cozonomono.query(instance, "?[id, name] <- [[2, 'Bob']] :put users {id => name}")

    assert_receive {:cozo_callback, :put, %NamedRows{rows: [[1, "Alice"]]}, _}, 1_000
    assert_receive {:cozo_callback, :put, %NamedRows{rows: [[2, "Bob"]]}, _}, 1_000
  end

  test "unregister_callback stops messages", %{instance: instance} do
    {:ok, cb_id} = Cozonomono.register_callback(instance, "users")

    assert Cozonomono.unregister_callback(instance, cb_id) == true

    Cozonomono.query(instance, "?[id, name] <- [[1, 'Alice']] :put users {id => name}")

    refute_receive {:cozo_callback, _, _, _}, 200
  end

  test "unregister_callback returns false for unknown id", %{instance: instance} do
    assert Cozonomono.unregister_callback(instance, 999_999) == false
  end

  test "callback with custom pid", %{instance: instance} do
    task =
      Task.async(fn ->
        receive do
          {:cozo_callback, :put, %NamedRows{}, %NamedRows{}} -> :got_it
        after
          2_000 -> :timeout
        end
      end)

    {:ok, _cb_id} = Cozonomono.register_callback(instance, "users", pid: task.pid)

    Cozonomono.query(instance, "?[id, name] <- [[1, 'Alice']] :put users {id => name}")

    assert Task.await(task, 3_000) == :got_it

    # The test process should NOT have received the callback
    refute_receive {:cozo_callback, _, _, _}, 100
  end

  test "callback with bounded capacity", %{instance: instance} do
    {:ok, cb_id} = Cozonomono.register_callback(instance, "users", capacity: 10)

    Cozonomono.query(instance, "?[id, name] <- [[1, 'Alice']] :put users {id => name}")

    assert_receive {:cozo_callback, :put, %NamedRows{}, %NamedRows{}}, 1_000

    assert Cozonomono.unregister_callback(instance, cb_id) == true
  end

  test "multiple callbacks on the same relation", %{instance: instance} do
    {:ok, cb_id1} = Cozonomono.register_callback(instance, "users")
    {:ok, cb_id2} = Cozonomono.register_callback(instance, "users")

    Cozonomono.query(instance, "?[id, name] <- [[1, 'Alice']] :put users {id => name}")

    # Should receive two messages (one per callback)
    assert_receive {:cozo_callback, :put, %NamedRows{}, %NamedRows{}}, 1_000
    assert_receive {:cozo_callback, :put, %NamedRows{}, %NamedRows{}}, 1_000

    Cozonomono.unregister_callback(instance, cb_id1)
    Cozonomono.unregister_callback(instance, cb_id2)
  end
end
