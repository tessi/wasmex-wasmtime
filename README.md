<p align="center">
  <img width="300" src="./logo.svg" alt="Wasmex logo">
</p>
<p align="center">
  <a href="https://github.com/tessi/wasmex/blob/master/LICENSE">
    <img src="https://img.shields.io/github/license/tessi/wasmex.svg" alt="License">
  </a>
  <a href="https://github.com/tessi/wasmex/actions/workflows/elixir-ci.yaml">
    <img src="https://github.com/tessi/wasmex/actions/workflows/elixir-ci.yaml/badge.svg?branch=main" alt="CI">
  </a>
</p>

WasmexWasmtime is the Wasmtime backend for Wasmex, the fast and secure [WebAssembly](https://webassembly.org/) and [WASI](https://github.com/WebAssembly/WASI) runtime for Elixir.
It enables lightweight WebAssembly containers to be run in your Elixir backend.

It uses [wasmtime](https://wasmtime.dev/) to execute WASM binaries through a NIF.
We use [Rust](https://www.rust-lang.org/) to implement the NIF to make it as safe as possible.

## Install

The package can be installed by adding `wasmex_wasmtime` to your list of
dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:wasmex_wasmtime, "~> 0.8.0"}
  ]
end
```

The docs can be found at [https://hexdocs.pm/wasmex](https://hexdocs.pm/wasmex/Wasmex.html).

It is easiest to use this project through the [wasmex](https://github.com/tessi/wasmex) interface.

## License

The entire project is under the MIT License. Please read [the`LICENSE` file](https://github.com/tessi/wasmex/blob/master/LICENSE).
