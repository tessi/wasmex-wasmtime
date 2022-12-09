defmodule WasmexWasmtime.MixProject do
  use Mix.Project

  @version "0.1.0-dev"

  def project do
    [
      app: :wasmex_wasmtime,
      version: @version,
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      name: "wasmex_wasmtime",
      description: description(),
      package: package(),
      deps: deps(),
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
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
      {:rustler_precompiled, "~> 0.5.4"},
      {:rustler, "~> 0.26.0", optional: true},
      {:ex_doc, "~> 0.29.1", only: [:dev, :test]},
      {:dialyxir, "~> 1.2.0", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.3", only: [:dev, :test], runtime: false}
    ]
  end

  defp description() do
    "wasmex_wasmtime is an Elixir library for executing WebAssembly binaries with wasmtime"
  end

  defp package() do
    [
      # These are the default files included in the package
      files: ~w[
        lib
        native/wasmex_wasmtime/src
        native/wasmex_wasmtime/Cargo.*
        native/wasmex_wasmtime/README.md
        native/wasmex_wasmtime/.cargo
        checksum-Elixir.WasmexWasmtime.Native.exs
        .formatter.exs
        mix.exs
        README.md
        LICENSE.md
        CHANGELOG.md
        ],
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/tessi/wasmex-wasmtime",
        "Docs" => "https://hexdocs.pm/wasmex_wasmtime"
      },
      source_url: "https://github.com/tessi/wasmex-wasmtime"
    ]
  end
end
