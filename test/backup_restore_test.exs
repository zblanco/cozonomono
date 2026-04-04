defmodule Cozonomono.BackupRestoreTest do
  use ExUnit.Case
  alias Cozonomono.NamedRows

  defp tmp_backup_path do
    Path.join(System.tmp_dir!(), "cozonomono_backup_#{:rand.uniform(100_000)}.db")
  end

  describe "backup/2" do
    test "creates a backup file" do
      {:ok, instance} = Cozonomono.new()
      path = tmp_backup_path()
      on_exit(fn -> File.rm(path) end)

      {:ok, _} = Cozonomono.query(instance, ":create bak_test {id: Int => val: String}")

      {:ok, _} =
        Cozonomono.query(
          instance,
          "?[id, val] <- [[1, 'hello']] :put bak_test {id => val}"
        )

      assert :ok = Cozonomono.backup(instance, path)
      assert File.exists?(path)
    end
  end

  describe "restore/2" do
    test "restores data from a backup" do
      path = tmp_backup_path()
      on_exit(fn -> File.rm(path) end)

      # Create and populate source instance
      {:ok, src} = Cozonomono.new()
      {:ok, _} = Cozonomono.query(src, ":create restore_test {id: Int => val: String}")

      {:ok, _} =
        Cozonomono.query(
          src,
          "?[id, val] <- [[1, 'alpha'], [2, 'beta']] :put restore_test {id => val}"
        )

      assert :ok = Cozonomono.backup(src, path)

      # Restore into a new instance
      {:ok, dst} = Cozonomono.new()
      assert :ok = Cozonomono.restore(dst, path)

      assert {:ok, %NamedRows{rows: rows}} =
               Cozonomono.query(dst, "?[id, val] := *restore_test{id, val}")

      assert length(rows) == 2
      alpha = Enum.find(rows, fn [id | _] -> id == 1 end)
      assert alpha == [1, "alpha"]
    end

    test "restoring from non-existent file restores empty state" do
      {:ok, instance} = Cozonomono.new()
      # CozoDB's restore_backup creates a new SQLite file if it doesn't exist,
      # so this doesn't error — it just restores an empty database.
      assert :ok =
               Cozonomono.restore(
                 instance,
                 "/tmp/nonexistent_restore_#{:rand.uniform(100_000)}.db"
               )
    end
  end

  describe "import_from_backup/3" do
    test "selectively imports specific relations" do
      path = tmp_backup_path()
      on_exit(fn -> File.rm(path) end)

      # Create source with two relations
      {:ok, src} = Cozonomono.new()
      {:ok, _} = Cozonomono.query(src, ":create sel_a {id: Int => val: String}")
      {:ok, _} = Cozonomono.query(src, ":create sel_b {id: Int => flag: Bool}")

      {:ok, _} =
        Cozonomono.query(src, "?[id, val] <- [[1, 'x']] :put sel_a {id => val}")

      {:ok, _} =
        Cozonomono.query(src, "?[id, flag] <- [[1, true]] :put sel_b {id => flag}")

      assert :ok = Cozonomono.backup(src, path)

      # Import only sel_a into a new instance (relation must exist first)
      {:ok, dst} = Cozonomono.new()
      {:ok, _} = Cozonomono.query(dst, ":create sel_a {id: Int => val: String}")
      assert :ok = Cozonomono.import_from_backup(dst, path, ["sel_a"])

      # sel_a should be available
      assert {:ok, %NamedRows{rows: [[1, "x"]]}} =
               Cozonomono.query(dst, "?[id, val] := *sel_a{id, val}")

      # sel_b should not exist
      assert {:error, _} =
               Cozonomono.query(dst, "?[id, flag] := *sel_b{id, flag}")
    end
  end

  describe "backup → restore round-trip" do
    test "full data round-trip through backup file" do
      path = tmp_backup_path()
      on_exit(fn -> File.rm(path) end)

      {:ok, src} = Cozonomono.new()

      {:ok, _} =
        Cozonomono.query(src, ":create rt_rel {id: Int => name: String, active: Bool}")

      {:ok, _} =
        Cozonomono.query(
          src,
          "?[id, name, active] <- [[1, 'Alice', true], [2, 'Bob', false]] :put rt_rel {id => name, active}"
        )

      assert :ok = Cozonomono.backup(src, path)

      {:ok, dst} = Cozonomono.new()
      assert :ok = Cozonomono.restore(dst, path)

      assert {:ok, %NamedRows{rows: rows}} =
               Cozonomono.query(dst, "?[id, name, active] := *rt_rel{id, name, active}")

      assert length(rows) == 2
      alice = Enum.find(rows, fn [id | _] -> id == 1 end)
      assert alice == [1, "Alice", true]
    end
  end
end
