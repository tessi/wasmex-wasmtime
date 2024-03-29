defmodule WasmexWasmtimeTest do
  use ExUnit.Case, async: true
  doctest WasmexWasmtime

  defp create_instance(_context) do
    %{module: module, store: store} = TestHelper.wasm_module()
    instance = start_supervised!({WasmexWasmtime, %{store: store, module: module}})
    %{instance: instance, module: module, store: store}
  end

  describe "when instantiating without imports" do
    setup [:create_instance]

    test "function_exists", %{instance: instance} do
      assert WasmexWasmtime.function_exists(instance, :arity_0)
      assert WasmexWasmtime.function_exists(instance, "arity_0")

      assert !WasmexWasmtime.function_exists(instance, :unknown_function)
      assert !WasmexWasmtime.function_exists(instance, "unknown_function")
    end

    test "call_function: calling an unknown function", %{instance: instance} do
      assert {:error, "exported function `unknown_function` not found"} =
               WasmexWasmtime.call_function(instance, :unknown_function, [1])
    end

    test "call_function: arity0 with too many params", %{instance: instance} do
      assert {:error, "number of params does not match. expected 0, got 1"} =
               WasmexWasmtime.call_function(instance, :arity_0, [1])
    end

    test "call_function: arity0 -> i32", %{instance: instance} do
      assert {:ok, [42]} = WasmexWasmtime.call_function(instance, :arity_0, [])
      assert {:ok, [42]} = WasmexWasmtime.call_function(instance, "arity_0", [])
    end

    test "call_function: sum(i32, i32) -> i32 function", %{instance: instance} do
      assert {:ok, [42]} == WasmexWasmtime.call_function(instance, :sum, [50, -8])
    end

    test "call_function: i32_i32(i32) -> i32 function", %{instance: instance} do
      assert {:ok, [-3]} == WasmexWasmtime.call_function(instance, :i32_i32, [-3])

      # giving a value greater than i32::max_value()
      # see: https://doc.rust-lang.org/std/primitive.i32.html#method.max_value
      assert {:error, "Cannot convert argument #1 to a WebAssembly i32 value."} ==
               WasmexWasmtime.call_function(instance, :i32_i32, [3_000_000_000])
    end

    test "call_function: i64_i64(i64) -> i64 function", %{instance: instance} do
      assert {:ok, [-3]} == WasmexWasmtime.call_function(instance, :i64_i64, [-3])

      # giving a value greater than i32::max_value()
      # see: https://doc.rust-lang.org/std/primitive.i32.html#method.max_value
      assert {:ok, [3_000_000_000]} ==
               WasmexWasmtime.call_function(instance, "i64_i64", [3_000_000_000])
    end

    test "call_function: f32_f32(f32) -> f32 function", %{instance: instance} do
      {:ok, [result]} = WasmexWasmtime.call_function(instance, :f32_f32, [3.14])

      assert_in_delta 3.14,
                      result,
                      0.001

      # a value greater than f32::max_value()
      assert {:error, "Cannot convert argument #1 to a WebAssembly f32 value."} ==
               WasmexWasmtime.call_function(instance, :f32_f32, [3.5e38])
    end

    test "call_function: f64_f64(f64) -> f64 function", %{instance: instance} do
      {:ok, [result]} = WasmexWasmtime.call_function(instance, :f64_f64, [3.14])

      assert_in_delta 3.14,
                      result,
                      0.001

      # a value greater than f32::max_value()
      assert {:ok, [3.5e38]} == WasmexWasmtime.call_function(instance, :f64_f64, [3.5e38])
    end

    test "call_function: i32_i64_f32_f64_f64(i32, i64, f32, f64) -> f64 function", %{
      instance: instance
    } do
      {:ok, [result]} =
        WasmexWasmtime.call_function(instance, :i32_i64_f32_f64_f64, [3, 4, 5.6, 7.8])

      assert_in_delta 20.4,
                      result,
                      0.001
    end

    test "call_function: bool_casted_to_i32() -> i32 function", %{instance: instance} do
      assert {:ok, [1]} == WasmexWasmtime.call_function(instance, :bool_casted_to_i32, [])
    end

    test "call_function: void() -> () function", %{instance: instance} do
      assert {:ok, []} == WasmexWasmtime.call_function(instance, :void, [])
    end

    test "call_function: string() -> string function", %{store: store, instance: instance} do
      {:ok, [pointer]} = WasmexWasmtime.call_function(instance, :string, [])
      {:ok, memory} = WasmexWasmtime.memory(instance)
      assert WasmexWasmtime.Memory.read_string(store, memory, pointer, 13) == "Hello, World!"
    end

    test "call_function: string_first_byte(string_pointer) -> u8 function", %{
      store: store,
      instance: instance
    } do
      {:ok, memory} = WasmexWasmtime.memory(instance)
      string = "hello, world"
      index = 42
      WasmexWasmtime.Memory.write_binary(store, memory, index, string)

      assert {:ok, [104]} ==
               WasmexWasmtime.call_function(instance, :string_first_byte, [
                 index,
                 String.length(string)
               ])
    end
  end

  # deadlocks
  test "read and manipulate memory in a callback" do
    %{store: store, module: module} = TestHelper.wasm_import_module()

    imports = %{
      env:
        TestHelper.default_imported_functions_env()
        |> Map.put(
          :imported_sum3,
          {:fn, [:i32, :i32, :i32], [:i32],
           fn context, a, b, c ->
             assert 42 == WasmexWasmtime.Memory.get_byte(context.caller, context.memory, 0)
             WasmexWasmtime.Memory.set_byte(context.caller, context.memory, 0, 23)
             a + b + c
           end}
        )
    }

    instance =
      start_supervised!({WasmexWasmtime, %{store: store, module: module, imports: imports}})

    {:ok, memory} = WasmexWasmtime.memory(instance)
    WasmexWasmtime.Memory.set_byte(store, memory, 0, 42)

    # asserts that the byte at memory[0] was set to 42 and then sets it to 23
    {:ok, _} = WasmexWasmtime.call_function(instance, :using_imported_sum3, [1, 2, 3])

    assert 23 == WasmexWasmtime.Memory.get_byte(store, memory, 0)
  end

  describe "when instantiating with imports" do
    def create_instance_with_atom_imports(_context) do
      imports = %{
        env: TestHelper.default_imported_functions_env()
      }

      %{store: store, module: module} = TestHelper.wasm_import_module()

      instance =
        start_supervised!({WasmexWasmtime, %{store: store, module: module, imports: imports}})

      %{store: store, module: module, imports: imports, instance: instance}
    end

    setup [:create_instance_with_atom_imports]

    test "call_function using_imported_void for void() -> () callback", %{instance: instance} do
      assert {:ok, []} == WasmexWasmtime.call_function(instance, :using_imported_void, [])
    end

    test "call_function using_imported_sum3", %{instance: instance} do
      assert {:ok, [44]} ==
               WasmexWasmtime.call_function(instance, :using_imported_sum3, [23, 19, 2])

      assert {:ok, [28]} ==
               WasmexWasmtime.call_function(instance, :using_imported_sum3, [100, -77, 5])
    end

    test "call_function using_imported_sumf", %{instance: instance} do
      {:ok, [result]} = WasmexWasmtime.call_function(instance, :using_imported_sumf, [2.3, 1.9])
      assert_in_delta 4.2, result, 0.001

      assert {:ok, [result]} =
               WasmexWasmtime.call_function(instance, :using_imported_sumf, [10.0, -7.7])

      assert_in_delta 2.3, result, 0.001
    end
  end

  describe "when instantiating with imports using string keys for the imports object" do
    def create_instance_with_string_imports(_context) do
      imports = %{
        "env" => TestHelper.default_imported_functions_env_stringified()
      }

      %{store: store, module: module} = TestHelper.wasm_import_module()

      instance =
        start_supervised!({WasmexWasmtime, %{store: store, module: module, imports: imports}})

      %{store: store, module: module, instance: instance}
    end

    setup [:create_instance_with_string_imports]

    test "call_function using_imported_sum3 with both, string and atom, identifiers", %{
      instance: instance
    } do
      assert {:ok, [6]} ==
               WasmexWasmtime.call_function(instance, "using_imported_sum3", [1, 2, 3])

      assert {:ok, [6]} == WasmexWasmtime.call_function(instance, :using_imported_sum3, [1, 2, 3])
    end
  end

  describe "when instantiating with imports that raise exceptions" do
    def create_instance_with_imports_raising_exceptions(_context) do
      imports = %{
        env: %{
          imported_sum3:
            {:fn, [:i32, :i32, :i32], [:i32], fn _context, _a, _b, _c -> raise("oops") end},
          imported_sumf: {:fn, [:f32, :f32], [:f32], fn _context, _a, _b -> raise("oops") end},
          imported_void: {:fn, [], [], fn _context -> raise("oops") end}
        }
      }

      %{store: store, module: module} = TestHelper.wasm_import_module()

      instance =
        start_supervised!({WasmexWasmtime, %{store: store, module: module, imports: imports}})

      %{store: store, module: module, instance: instance}
    end

    setup [:create_instance_with_imports_raising_exceptions]

    test "call_function using_imported_sum3 with both, string and atom, identifiers", %{
      instance: instance
    } do
      assert {:error, reason} =
               WasmexWasmtime.call_function(instance, "using_imported_sum3", [1, 2, 3])

      assert reason =~
               "Error during function excecution: `error while executing at wasm backtrace:\n    0:  0x12e - <unknown>!using_imported_sum3"
    end
  end
end
