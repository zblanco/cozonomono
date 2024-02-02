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
  defp err, do: :erlang.nif_error(:nif_not_loaded)
end
