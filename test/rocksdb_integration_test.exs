defmodule Cozonomono.RocksDBIntegrationTest do
  use ExUnit.Case, async: true

  test "RocksDB transactions survive owner exit and portable backup restores" do
    root = Path.join(System.tmp_dir!(), "cozo-rocks-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    parent = self()
    owner = start_supervised!({Task, fn ->
      {:ok, db} = Cozonomono.new(:rocksdb, Path.join(root, "db"))
      {:ok, _} = Cozonomono.query(db, ":create facts {id: Int => text: String}")
      {:ok, tx} = Cozonomono.multi_transaction(db)
      {:ok, _} = Cozonomono.tx_query(tx, "?[id, text] <- [[1, 'remembered']] :put facts {id => text}")
      :ok = Cozonomono.tx_commit(tx)
      :ok = Cozonomono.backup(db, Path.join(root, "backup.sqlite"))
      send(parent, :written)
      receive do :stop -> :ok end
    end})
    assert_receive :written, 10_000
    ref = Process.monitor(owner)
    send(owner, :stop)
    assert_receive {:DOWN, ^ref, :process, ^owner, :normal}
    {:ok, reopened} = Cozonomono.new(:rocksdb, Path.join(root, "db"))
    assert {:ok, %{rows: [["remembered"]]}} = Cozonomono.query(reopened, "?[text] := *facts{text}")
    {:ok, restored} = Cozonomono.new(:rocksdb, Path.join(root, "restored"))
    assert :ok = Cozonomono.restore(restored, Path.join(root, "backup.sqlite"))
    assert {:ok, %{rows: [["remembered"]]}} = Cozonomono.query(restored, "?[text] := *facts{text}")
  end
end
