<p align="center">
  <img width="300" src="./logo.svg" alt="Wasmex logo">
</p>
<p align="center">
  <a href="https://github.com/tessi/wasmex-wasmtime/blob/master/LICENSE">
    <img src="https://img.shields.io/github/license/tessi/wasmex-wasmtime.svg" alt="License">
  </a>
  <a href="https://github.com/tessi/wasmex-wasmtime/actions/workflows/elixir-ci.yaml">
    <img src="https://github.com/tessi/wasmex-wasmtime/actions/workflows/elixir-ci.yaml/badge.svg?branch=main" alt="CI">
  </a>
</p>

This is an experiment to see what it takes to implement [wasmex](https://github.com/tessi/wasmex) for [wasmtime](https://wasmtime.dev/).

Main changes to wasmex are:

* changed underlying WASM rust library from wasmer to wasmtime
* renamed to `wasmex_wasmtime`
* introduced the concept of a `Store` (probably something that is needed wor wasmer too very soon). the store needs to be passed to many function calls
* moved WASI params (env, args, options) to module compilation instead of instance creation
* removed Module.set_name (this functionality doesn't exist on wasmtime)
* removed memory views (wasmex memory can be "viewed" as u8, u16, i8, i16, ...), now we only have u8 memory. This simplifies the code a lot. probably something we should consider for wasmex too
* re-implemented pipes

Main open TODOs:

* fix/update/write documentation. Currently we mostly copied wasmex docs which are not accurate
* fix tests and bugs causing test failures :)
* compare with wasmex (speed, usability)
* ask community for feedback

## License

The entire project is under the MIT License. Please read [the`LICENSE` file](https://github.com/tessi/wasmex-wasmtime/blob/master/LICENSE).
