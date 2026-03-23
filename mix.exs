defmodule Cozonomono.MixProject do
  use Mix.Project

  @version "0.1.0-dev"
  @dev? String.ends_with?(@version, "-dev")
  @force_build? System.get_env("COZONOMONO_BUILD") in ["1", "true"]

  def project do
    [
      app: :cozonomono,
      version: "0.1.0-dev",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: [
        "rust.lint": [
          "cmd cargo clippy --manifest-path=native/cozonomono_cozo/Cargo.toml -- -Dwarnings"
        ],
        "rust.fmt": ["cmd cargo fmt --manifest-path=native/cozonomono_cozo/Cargo.toml --all"],
        ci: ["format", "rust.fmt", "rust.lint", "test"]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:rustler_precompiled, "~> 0.7"},
      {:rustler, "~> 0.30.0", optional: not (@dev? or @force_build?)}
    ]
  end
end
