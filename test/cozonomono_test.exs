defmodule CozonomonoTest do
  use ExUnit.Case
  alias Cozonomono.Instance
  doctest Cozonomono

  test "can create an instance" do
    assert {:ok, %Instance{path: "", resource: _, engine: "mem"}} = Cozonomono.new()
  end

  test "can execute basic queries" do
    {:ok, instance} = Cozonomono.new()

    assert Cozonomono.query(instance, "?[] <- [['hello', 'world', 'Cozo!']]") ==
             {:ok,
              %{
                "headers" => ["_0", "_1", "_2"],
                "next" => nil,
                "rows" => [["hello", "world", "Cozo!"]]
              }}
  end

  test "can handle many data types" do
    {:ok, instance} = Cozonomono.new()

    assert Cozonomono.query(instance, "?[] <- [['hello', 100, 100.0, [1, 2, 3]]]") ==
             {:ok,
              %{
                "headers" => ["_0", "_1", "_2", "_3"],
                "next" => nil,
                "rows" => [["hello", 100, 100.0, [1, 2, 3]]]
              }}
  end

  test "can use params" do
    {:ok, instance} = Cozonomono.new()

    assert Cozonomono.query(instance, "?[] <- [['hello', $name]]", params: %{"name" => "Chris"}) ==
             {:ok,
              %{
                "headers" => ["_0", "_1"],
                "next" => nil,
                "rows" => [["hello", "Chris"]]
              }}
  end
end
