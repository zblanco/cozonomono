defmodule Cozonomono.Native do
  mix_config = Mix.Project.config()
  version = mix_config[:version]
  github_url = mix_config[:package][:links]["GitHub"]
  # Since Rustler 0.27.0, we need to change manually the mode for each env.
  # We want "debug" in dev and test because it's faster to compile.
  mode = if Mix.env() in [:dev, :test], do: :debug, else: :release

  use RustlerPrecompiled,
    otp_app: :cozonomono,
    crate: "cozonomono_cozo",
    base_url: "#{github_url}/releases/download/v#{version}",
    force_build: System.get_env("COZONOMONO_BUILD") in ["1", "true"],
    targets:
      Enum.uniq(["aarch64-unknown-linux-musl" | RustlerPrecompiled.Config.default_targets()]),
    version: version,
    mode: mode

  def create_instance(_engine, _path), do: err()
  def run_default(_instance, _payload), do: err()
  def run_script(_instance, _payload, _params, _immutable?), do: err()
  def export_relations(_instance, _relations), do: err()
  def import_relations(_instance, _data), do: err()
  def backup_db(_instance, _path), do: err()
  def restore_backup(_instance, _path), do: err()
  def import_from_backup(_instance, _path, _relations), do: err()
  def multi_transaction(_instance, _write), do: err()
  def tx_run_script(_tx, _payload, _params), do: err()
  def tx_commit(_tx), do: err()
  def tx_abort(_tx), do: err()
  def register_callback(_instance, _relation, _pid, _capacity), do: err()
  def unregister_callback(_instance, _id), do: err()
  def register_fixed_rule(_instance, _name, _return_arity, _pid), do: err()
  def respond_fixed_rule(_bridge, _request_id, _result), do: err()
  def unregister_fixed_rule(_instance, _name), do: err()
  def run_default_lazy(_instance, _payload), do: err()
  def run_script_lazy(_instance, _payload, _params, _immutable?), do: err()
  def tx_run_script_lazy(_tx, _payload, _params), do: err()
  def lazy_rows_next(_lazy), do: err()
  def lazy_rows_row_at(_lazy, _index), do: err()
  def lazy_rows_cell_at(_lazy, _row_index, _col_index), do: err()
  def lazy_rows_column_at(_lazy, _col_index), do: err()
  def lazy_rows_slice(_lazy, _offset, _length), do: err()
  def lazy_rows_to_named_rows(_lazy), do: err()
  def close_instance(_instance), do: err()
  defp err, do: :erlang.nif_error(:nif_not_loaded)
end
