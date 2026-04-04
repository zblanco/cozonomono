defmodule Cozonomono.MixProject do
  use Mix.Project

  @version "0.1.0-dev"
  @source_url "https://github.com/zblanco/cozonomono"
  @dev? String.ends_with?(@version, "-dev")
  @force_build? System.get_env("COZONOMONO_BUILD") in ["1", "true"]

  def project do
    [
      app: :cozonomono,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      package: package(),
      description: description(),
      docs: docs(),
      source_url: @source_url,
      homepage_url: @source_url,
      usage_rules: usage_rules()
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
      {:tidewave, "~> 0.5", only: :dev},
      {:bandit, "~> 1.0", only: :dev},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false},
      {:usage_rules, "~> 1.2", only: :dev, runtime: false},
      {:rustler, "~> 0.30.0", optional: not (@dev? or @force_build?)},
      {:benchee, "~> 1.3", only: :dev}
    ]
  end

  defp aliases do
    [
      "rust.lint": [
        "cmd cargo clippy --manifest-path=native/cozonomono_cozo/Cargo.toml -- -Dwarnings"
      ],
      "rust.fmt": ["cmd cargo fmt --manifest-path=native/cozonomono_cozo/Cargo.toml --all"],
      "agents.sync": ["usage_rules.sync"],
      ci: ["format", "rust.fmt", "rust.lint", "test"],
      tidewave:
        "run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4000) end)'"
    ]
  end

  defp description do
    "Elixir bindings for CozoDB with Rustler-powered NIFs, lazy result access, transactions, and operational APIs."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "CozoDB" => "https://github.com/cozodb/cozo",
        "Docs" => "https://docs.cozodb.org/en/latest/",
        "usage_rules" => "https://github.com/ash-project/usage_rules"
      },
      files: [
        ".formatter.exs",
        "lib",
        "native",
        "priv",
        "mix.exs",
        "README.md",
        "CHEATSHEET.md",
        "guides",
        "usage-rules.md",
        "usage-rules"
      ]
    ]
  end

  defp docs do
    guide_paths = Enum.sort(Path.wildcard("guides/*.md"))

    [
      main: "readme",
      source_ref: "main",
      extras: ["README.md", "CHEATSHEET.md" | guide_paths],
      groups_for_extras: [
        Overview: ["README.md", "CHEATSHEET.md"],
        Guides: guide_paths
      ],
      groups_for_modules: [
        Core: [Cozonomono],
        Data: [
          Cozonomono.Instance,
          Cozonomono.NamedRows,
          Cozonomono.LazyRows
        ],
        Runtime: [Cozonomono.Transaction, Cozonomono.FixedRuleBridge, Cozonomono.Native]
      ]
    ]
  end

  defp usage_rules do
    [
      file: ".usage-rules/AGENTS.md",
      usage_rules: [:elixir, :otp, :usage_rules],
      skills: [
        location: ".usage-rules/skills",
        package_skills: [:usage_rules]
      ]
    ]
  end
end
