defmodule Bastille.MixProject do
  use Mix.Project

  def project do
    [
      app: :bastille,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "A modular blockchain implementation in Elixir",
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :ssl],
      mod: {Bastille.Application, []}
    ]
  end

  defp deps do
    base_deps() ++ crypto_deps()
  end

  defp base_deps do
    [
      # JSON handling
      {:jason, "~> 1.4"},

      # Web interface
      {:plug_cowboy, "~> 2.7"},
      {:cors_plug, "~> 3.0"},

      # Database
      {:cubdb, "~> 2.0"},

      # Networking
      {:ranch, "~> 2.1"},

      # Protobuf (pure Elixir, no protoc required for inline schema)
      {:protobuf, "~> 0.15"},

      # Development tools
      {:ex_doc, "~> 0.38", only: :test, runtime: false},
      {:dialyxir, "~> 1.4", only: :test, runtime: false},
      {:credo, "~> 1.7", only: :test, runtime: false},

      # Testing
      {:req, "~> 0.5", only: :test}
    ]
  end

  defp crypto_deps do
    # Post-quantum cryptography avec Rustler - MODERNE ET FIABLE !
    [
      {:rustler, "~> 0.34"},        # Rustler pour NIFs Rust
      # Upstream version does not compile on OTP 27
      {:keccakf1600, git: "https://github.com/vitaliel/erlang-keccakf1600", branch: "fix/compile" } # Keccak hash
    ]
  end

  defp package do
    [
      maintainers: ["Bastille Team"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/bastille/bastille"}
    ]
  end

  defp docs do
    [
      main: "Bastille",
      extras: ["README.md"]
    ]
  end
end
