defmodule TestHelper do
  @wasm_test_source_dir "#{Path.dirname(__ENV__.file)}/wasm_test"
  @wasm_import_test_source_dir "#{Path.dirname(__ENV__.file)}/wasm_import_test"
  @wasi_test_source_dir "#{Path.dirname(__ENV__.file)}/wasi_test"

  def wasm_test_file_path,
    do: "#{@wasm_test_source_dir}/target/wasm32-unknown-unknown/debug/wasmex_wasmtime_test.wasm"

  def wasm_import_test_file_path,
    do:
      "#{@wasm_import_test_source_dir}/target/wasm32-unknown-unknown/debug/wasmex_wasmtime_test.wasm"

  def wasi_test_file_path,
    do: "#{@wasi_test_source_dir}/target/wasm32-wasi/debug/main.wasm"

  def precompile_wasm_files do
    {"", 0} = System.cmd("cargo", ["build"], cd: @wasm_test_source_dir)
    {"", 0} = System.cmd("cargo", ["build"], cd: @wasm_import_test_source_dir)
    {"", 0} = System.cmd("cargo", ["build"], cd: @wasi_test_source_dir)
  end

  def wasm_module do
    {:ok, store} = WasmexWasmtime.Store.new()

    {:ok, wasm_module} =
      WasmexWasmtime.Module.compile(store, File.read!(TestHelper.wasm_test_file_path()))

    %{store: store, module: wasm_module}
  end

  def wasm_import_module do
    {:ok, store} = WasmexWasmtime.Store.new()

    {:ok, wasm_module} =
      WasmexWasmtime.Module.compile(store, File.read!(TestHelper.wasm_import_test_file_path()))

    %{store: store, module: wasm_module}
  end

  def default_imported_functions_env do
    %{
      imported_sum3: {:fn, [:i32, :i32, :i32], [:i32], fn _context, a, b, c -> a + b + c end},
      imported_sumf: {:fn, [:f32, :f32], [:f32], fn _context, a, b -> a + b end},
      imported_void: {:fn, [], [], fn _context -> nil end}
    }
  end

  def default_imported_functions_env_stringified do
    default_imported_functions_env()
    |> Enum.map(fn {k, v} -> {to_string(k), v} end)
    |> Enum.into(%{})
  end
end

TestHelper.precompile_wasm_files()
ExUnit.start()
