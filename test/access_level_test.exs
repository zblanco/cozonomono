defmodule AccessLevelTest do
  use ExUnit.Case
  alias Cozonomono.NamedRows

  setup do
    {:ok, instance} = Cozonomono.new()
    Cozonomono.query(instance, ":create users {id: Int => name: String}")
    %{instance: instance}
  end

  test "set_access_level to read_only prevents writes", %{instance: instance} do
    Cozonomono.query(instance, "?[id, name] <- [[1, 'Alice']] :put users {id => name}")

    assert {:ok, %NamedRows{}} = Cozonomono.set_access_level(instance, "users", :read_only)

    assert {:error, _} =
             Cozonomono.query(instance, "?[id, name] <- [[2, 'Bob']] :put users {id => name}")

    # Reads still work
    assert {:ok, %NamedRows{rows: [[1, "Alice"]]}} =
             Cozonomono.query(instance, "?[id, name] := *users[id, name]")
  end

  test "set_access_level to protected prevents removal", %{instance: instance} do
    assert {:ok, %NamedRows{}} = Cozonomono.set_access_level(instance, "users", :protected)

    assert {:error, _} = Cozonomono.remove_relation(instance, "users")
  end

  test "set_access_level to hidden prevents writes", %{instance: instance} do
    assert {:ok, %NamedRows{}} = Cozonomono.set_access_level(instance, "users", :hidden)

    assert {:error, _} =
             Cozonomono.query(instance, "?[id, name] <- [[1, 'Alice']] :put users {id => name}")

    # Access level is reported in list_relations
    {:ok, %NamedRows{headers: headers, rows: rows}} = Cozonomono.list_relations(instance)
    access_idx = Enum.find_index(headers, &(&1 == "access_level"))
    user_row = Enum.find(rows, fn row -> Enum.at(row, 0) == "users" end)
    assert Enum.at(user_row, access_idx) == "hidden"
  end

  test "set_access_level back to normal restores access", %{instance: instance} do
    Cozonomono.set_access_level(instance, "users", :read_only)

    assert {:error, _} =
             Cozonomono.query(instance, "?[id, name] <- [[1, 'Alice']] :put users {id => name}")

    Cozonomono.set_access_level(instance, "users", :normal)

    assert {:ok, %NamedRows{}} =
             Cozonomono.query(instance, "?[id, name] <- [[1, 'Alice']] :put users {id => name}")
  end

  test "set_access_level on multiple relations", %{instance: instance} do
    Cozonomono.query(instance, ":create logs {id: Int => msg: String}")

    assert {:ok, %NamedRows{}} =
             Cozonomono.set_access_level(instance, ["users", "logs"], :read_only)

    assert {:error, _} =
             Cozonomono.query(instance, "?[id, name] <- [[1, 'Alice']] :put users {id => name}")

    assert {:error, _} =
             Cozonomono.query(instance, "?[id, msg] <- [[1, 'hello']] :put logs {id => msg}")
  end
end
