defmodule CozonomonoTest do
  use ExUnit.Case
  alias Cozonomono.Instance
  alias Cozonomono.NamedRows
  doctest Cozonomono

  test "can create an instance" do
    assert {:ok, %Instance{path: "", resource: _, engine: "mem"}} = Cozonomono.new()
  end

  test "can execute basic queries" do
    {:ok, instance} = Cozonomono.new()

    assert {:ok,
            %NamedRows{
              headers: ["_0", "_1", "_2"],
              rows: [["hello", "world", "Cozo!"]],
              next: nil
            }} = Cozonomono.query(instance, "?[] <- [['hello', 'world', 'Cozo!']]")
  end

  test "can handle many data types" do
    {:ok, instance} = Cozonomono.new()

    assert {:ok,
            %NamedRows{
              rows: [["hello", 100, 100.0, [1, 2, 3]]]
            }} = Cozonomono.query(instance, "?[] <- [['hello', 100, 100.0, [1, 2, 3]]]")
  end

  test "can use params" do
    {:ok, instance} = Cozonomono.new()

    assert {:ok, %NamedRows{rows: [["hello", "Chris"]]}} =
             Cozonomono.query(instance, "?[] <- [['hello', $name]]", params: %{"name" => "Chris"})
  end
end
