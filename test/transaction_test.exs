defmodule Cozonomono.TransactionTest do
  use ExUnit.Case
  alias Cozonomono.NamedRows
  alias Cozonomono.Transaction

  describe "multi_transaction/2" do
    test "creates a write transaction handle" do
      {:ok, instance} = Cozonomono.new()
      assert {:ok, %Transaction{write: true}} = Cozonomono.multi_transaction(instance)
    end

    test "creates a read-only transaction handle" do
      {:ok, instance} = Cozonomono.new()
      assert {:ok, %Transaction{write: false}} = Cozonomono.multi_transaction(instance, false)
    end
  end

  describe "tx_query/3 and tx_commit/1" do
    test "queries and commits within a transaction" do
      {:ok, instance} = Cozonomono.new()

      {:ok, _} =
        Cozonomono.query(instance, ":create tx_test {id: Int => name: String}")

      {:ok, tx} = Cozonomono.multi_transaction(instance)

      assert {:ok, %NamedRows{}} =
               Cozonomono.tx_query(
                 tx,
                 "?[id, name] <- [[1, 'Alice'], [2, 'Bob']] :put tx_test {id => name}"
               )

      assert :ok = Cozonomono.tx_commit(tx)

      # Data should be visible after commit
      assert {:ok, %NamedRows{rows: rows}} =
               Cozonomono.query(instance, "?[id, name] := *tx_test{id, name}")

      assert length(rows) == 2
    end

    test "multiple queries in a single transaction" do
      {:ok, instance} = Cozonomono.new()

      {:ok, _} =
        Cozonomono.query(instance, ":create multi_q {id: Int => val: String}")

      {:ok, tx} = Cozonomono.multi_transaction(instance)

      {:ok, _} =
        Cozonomono.tx_query(tx, "?[id, val] <- [[1, 'first']] :put multi_q {id => val}")

      {:ok, _} =
        Cozonomono.tx_query(tx, "?[id, val] <- [[2, 'second']] :put multi_q {id => val}")

      # Read within the transaction
      assert {:ok, %NamedRows{rows: rows}} =
               Cozonomono.tx_query(tx, "?[id, val] := *multi_q{id, val}")

      assert length(rows) == 2
      assert :ok = Cozonomono.tx_commit(tx)
    end

    test "query with params in transaction" do
      {:ok, instance} = Cozonomono.new()

      {:ok, _} =
        Cozonomono.query(instance, ":create param_tx {id: Int => name: String}")

      {:ok, tx} = Cozonomono.multi_transaction(instance)

      assert {:ok, %NamedRows{}} =
               Cozonomono.tx_query(
                 tx,
                 "?[id, name] <- [[$id, $name]] :put param_tx {id => name}",
                 %{"id" => 1, "name" => "Alice"}
               )

      assert :ok = Cozonomono.tx_commit(tx)

      assert {:ok, %NamedRows{rows: [[1, "Alice"]]}} =
               Cozonomono.query(instance, "?[id, name] := *param_tx{id, name}")
    end
  end

  describe "tx_abort/1" do
    test "aborted transaction discards changes" do
      {:ok, instance} = Cozonomono.new()

      {:ok, _} =
        Cozonomono.query(instance, ":create abort_test {id: Int => val: String}")

      {:ok, tx} = Cozonomono.multi_transaction(instance)

      {:ok, _} =
        Cozonomono.tx_query(
          tx,
          "?[id, val] <- [[1, 'should_vanish']] :put abort_test {id => val}"
        )

      assert :ok = Cozonomono.tx_abort(tx)

      # Data should not be persisted after abort
      assert {:ok, %NamedRows{rows: []}} =
               Cozonomono.query(instance, "?[id, val] := *abort_test{id, val}")
    end
  end

  describe "read-only transaction" do
    test "can read data in a read-only transaction" do
      {:ok, instance} = Cozonomono.new()

      {:ok, _} =
        Cozonomono.query(instance, ":create ro_test {id: Int => val: String}")

      {:ok, _} =
        Cozonomono.query(instance, "?[id, val] <- [[1, 'hello']] :put ro_test {id => val}")

      {:ok, tx} = Cozonomono.multi_transaction(instance, false)

      assert {:ok, %NamedRows{rows: [[1, "hello"]]}} =
               Cozonomono.tx_query(tx, "?[id, val] := *ro_test{id, val}")

      assert :ok = Cozonomono.tx_commit(tx)
    end
  end
end
