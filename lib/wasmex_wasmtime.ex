defmodule WasmexWasmtime do
  @moduledoc """
  WasmexWasmtime is a fast and secure [WebAssembly](https://webassembly.org/) and [WASI](https://github.com/WebAssembly/WASI) runtime for Elixir.
  It enables lightweight WebAssembly containers to be run in your Elixir backend.

  It uses [wasmer](https://wasmer.io/) to execute WASM binaries through a NIF. We use [Rust](https://www.rust-lang.org/) to implement the NIF to make it as safe as possible.

  This is the main module, providing most of the needed API to run WASM binaries.

  Each WASM module must be compiled from a `.wasm` file.
  A compiled module can be instantiated which usually happens in a [GenServer](https://hexdocs.pm/elixir/master/GenServer.html).
  To start the GenServer, `start_link/1` is used - it receives a variety of configuration options including function imports and optional WASI runtime options.

      {:ok, bytes } = File.read("wasmex_wasmtime_test.wasm")
      {:ok, module} = WasmexWasmtime.Module.compile(bytes)
      {:ok, instance } = WasmexWasmtime.start_link(%{module: module})
      {:ok, [42]} == WasmexWasmtime.call_function(instance, "sum", [50, -8])

  Memory of a WASM instance can be read/written using `WasmexWasmtime.Memory`:

      offset = 7
      index = 4
      value = 42

      {:ok, memory} = WasmexWasmtime.Instance.memory(instance, :uint8, offset)
      WasmexWasmtime.Memory.set(memory, index, value)
      IO.puts WasmexWasmtime.Memory.get(memory, index) # 42

  See `start_link/1` for starting a WASM instance and `call_function/3` for details about calling WASM functions.
  """
  use GenServer

  # Client

  @doc """
  Starts a GenServer which instantiates a WASM module from the given `.wasm` bytes.

      {:ok, bytes } = File.read("wasmex_wasmtime_test.wasm")
      {:ok, module} = WasmexWasmtime.Module.compile(bytes)
      {:ok, instance } = WasmexWasmtime.start_link(%{module: module})
      {:ok, [42]} == WasmexWasmtime.call_function(instance, "sum", [50, -8])

  ### Imports

  Imports are provided as a map of namespaces, each namespace being a nested map of imported functions:

      imports = %{
        env: %{
          sum3: {:fn, [:i32, :i32, :i32], [:i32], fn (_context, a, b, c) -> a + b + c end},
        }
      }
      instance = WasmexWasmtime.start_link(%{module: module, imports: imports})
      {:ok, [6]} = WasmexWasmtime.call_function(instance, "use_the_imported_sum_fn", [1, 2, 3])

  In the example above, we import the `"env"` namespace.
  Each namespace is a map listing imports, e.g. the `sum3` function, which is represented with a tuple of:

  1. the import type: `:fn` (a function),
  1. the functions parameter types: `[:i32, :i32]`,
  1. the functions return types: `[:i32]`, and
  1. the function to be executed: `fn (_context, a, b, c) -> a + b end`

  The first param the function receives is always the call context (a Map containing e.g. the instances memory).
  All other params are regular parameters as specified by the parameter type list.

  Valid parameter/return types are:

  - `:i32` a 32 bit integer
  - `:i64` a 64 bit integer
  - `:f32` a 32 bit float
  - `:f64` a 64 bit float

  The return type must always be one value.

  ### WASI

  Optionally, modules can be run with WebAssembly System Interface (WASI) support.
  WASI functions are provided as native NIF functions by default.

      {:ok, instance } = WasmexWasmtime.start_link(%{module: module, wasi: true})

  It is possible to overwrite the default WASI functions using the imports map as described above.

  Oftentimes, WASI programs need additional input like environment variables, arguments,
  or file system access.
  These can be provided by giving a `wasi` map:

      wasi = %Wasmex.Wasi.WasiOptions{
        args: ["hello", "from elixir"],
        env: %{
          "A_NAME_MAPS" => "to a value",
          "THE_TEST_WASI_FILE" => "prints all environment variables"
        },
        preopen: [%Wasmex.Wasi.PreopenOption{path: "logfile", alias: "log"}]
      }
      {:ok, instance } = WasmexWasmtime.start_link(%{module: module, wasi: wasi})

  It is also possible to capture stdout, stdin, or stderr of a WASI program using pipes:

      {:ok, stdin} = WasmexWasmtime.Pipe.create()
      {:ok, stdout} = WasmexWasmtime.Pipe.create()
      {:ok, stderr} = WasmexWasmtime.Pipe.create()
      wasi = %Wasmex.Wasi.WasiOptions{
        stdin: stdin,
        stdout: stdout,
        stderr: stderr
      }
      {:ok, instance } = WasmexWasmtime.start_link(%{module: module, wasi: wasi})
      WasmexWasmtime.Pipe.write(stdin, "Hey! It compiles! Ship it!")
      {:ok, _} = WasmexWasmtime.call_function(instance, :_start, [])
      WasmexWasmtime.Pipe.read(stdout)
  """
  def start_link(%{} = opts) when not is_map_key(opts, :imports),
    do: start_link(Map.merge(opts, %{imports: %{}}))

  def start_link(%{} = opts) when is_map_key(opts, :module) and not is_map_key(opts, :store),
    do: {:error, :must_specify_store_used_to_compile_module}

  def start_link(%{wasi: true} = opts),
    do: start_link(Map.merge(opts, %{wasi: %WasmexWasmtime.Wasi.WasiOptions{}}))

  def start_link(%{bytes: bytes} = opts) do
    with {:ok, store} <- build_store(opts),
         {:ok, module} <- WasmexWasmtime.Module.compile(store, bytes) do
      opts
      |> Map.delete(:bytes)
      |> Map.put(:module, module)
      |> Map.put(:store, store)
      |> start_link()
    end
  end

  def start_link(%{store: store, module: module, imports: imports}) when is_map(imports) do
    GenServer.start_link(__MODULE__, %{
      store: store,
      module: module,
      imports: stringify_keys(imports)
    })
  end

  defp build_store(opts) do
    if Map.has_key?(opts, :wasi) do
      WasmexWasmtime.Store.new_wasi(stringify_keys(opts[:wasi]))
    else
      WasmexWasmtime.Store.new()
    end
  end

  @doc """
  Returns whether a function export with the given `name` exists in the WebAssembly instance.
  """
  def function_exists(pid, name) do
    GenServer.call(pid, {:exported_function_exists, stringify(name)})
  end

  @doc """
  Calls a function with the given `name` and `params` on
  the WebAssembly instance and returns its results.

  ### Strings as Parameters and Return Values

  Strings can not directly be used as parameters or return values when calling WebAssembly functions since WebAssembly only knows number data types.
  But since Strings are just "a bunch of bytes" we can write these bytes into memory and give our WebAssembly function a pointer to that memory location.

  #### Strings as Function Parameters

  Given we have the following Rust function that returns the first byte of a given string
  in our WebAssembly (note: this is copied from our test code, have a look there if you're interested):

  ```rust
  #[no_mangle]
  pub extern "C" fn string_first_byte(bytes: *const u8, length: usize) -> u8 {
      let slice = unsafe { slice::from_raw_parts(bytes, length) };
      match slice.first() {
          Some(&i) => i,
          None => 0,
      }
  }
  ```

  Let's see how we can call this function from Elixir:

  ```elixir
  {:ok, instance} = WasmexWasmtime.start_link(%{module: module})
  {:ok, memory} = WasmexWasmtime.memory(instance, :uint8, 0)
  index = 42
  string = "hello, world"
  WasmexWasmtime.Memory.write_binary(memory, index, string)

  # 104 is the letter "h" in ASCII/UTF-8 encoding
  {:ok, [104]} == WasmexWasmtime.call_function(instance, "string_first_byte", [index, String.length(string)])
  ```

  Please not that Elixir and Rust assume Strings to be valid UTF-8. Take care when handling other encodings.

  #### Strings as Function Return Values

  Given we have the following Rust function in our WebAssembly (copied from our test code):

  ```rust
  #[no_mangle]
  pub extern "C" fn string() -> *const u8 {
      b"Hello, World!".as_ptr()
  }
  ```

  This function returns a pointer to its memory.
  This memory location contains the String "Hello, World!" (ending with a null-byte since in C-land all strings end with a null-byte to mark the end of the string).

  This is how we would receive this String in Elixir:

  ```elixir
  {:ok, instance} = WasmexWasmtime.start_link(%{module: module})
  {:ok, memory} = WasmexWasmtime.memory(instance, :uint8, 0)

  {:ok, [pointer]} = WasmexWasmtime.call_function(instance, "string", [])
  returned_string = WasmexWasmtime.Memory.read_string(memory, pointer, 13) # "Hello, World!"
  ```

  #### Specifying a timeout
  The default timeout for `call_function` is 5 seconds, or 5000 milliseconds. If you're calling a long-running function, you can specify a timeout value (in milliseconds) for this call. Using the above example as a starting point, calling a function with a timeout of 10 seconds looks like:
  ```elixir
  {:ok, [pointer]} = WasmexWasmtime.call_function(instance, "string", [], 10000)
  ```
  """
  def call_function(pid, name, params, timeout \\ 5000) do
    GenServer.call(pid, {:call_function, stringify(name), params}, timeout)
  end

  @doc """
  Finds the exported memory of the given WASM instance and returns it as a `WasmexWasmtime.Memory`.

  The memory is a sequence of bytes.
  """
  def memory(pid) do
    GenServer.call(pid, {:memory})
  end

  defp stringify_keys(struct) when is_struct(struct), do: struct

  defp stringify_keys(map) when is_map(map) do
    for {key, val} <- map, into: %{}, do: {stringify(key), stringify_keys(val)}
  end

  defp stringify_keys(value), do: value

  defp stringify(s) when is_binary(s), do: s
  defp stringify(s) when is_atom(s), do: Atom.to_string(s)

  # Server

  @doc """
  Params:

  * module (WasmexWasmtime.Module): the compiled WASM module
  * imports (map): a map defining imports. Structure is:
                   %{
                     namespace_name: %{
                       import_name: {:fn, [:i32, :i32], [:i32], function_reference}
                     }
                   }
  * wasi (map): a map defining WASI support. Structure is:
                %{
                  args: ["string", "arguments"],
                  env: %{
                    "A_NAME_MAPS" => "to a value"
                  },
                  stdin: Pipe.create(),
                  stdout: Pipe.create(),
                  stderr: Pipe.create()
                }
  """
  @impl true
  def init(%{store: store, module: module, imports: imports} = state) when is_map(imports) do
    case WasmexWasmtime.Instance.new(store, module, imports) do
      {:ok, instance} -> {:ok, Map.merge(state, %{instance: instance})}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def handle_call({:memory}, _from, %{store: store, instance: instance} = state) do
    case WasmexWasmtime.Memory.from_instance(store, instance) do
      {:ok, memory} -> {:reply, {:ok, memory}, state}
      {:error, error} -> {:reply, {:error, error}, state}
    end
  end

  @impl true
  def handle_call(
        {:exported_function_exists, name},
        _from,
        %{store: store, instance: instance} = state
      )
      when is_binary(name) do
    {:reply, WasmexWasmtime.Instance.function_export_exists(store, instance, name), state}
  end

  @impl true
  def handle_call(
        {:call_function, name, params},
        from,
        %{store: store, instance: instance} = state
      ) do
    :ok = WasmexWasmtime.Instance.call_exported_function(store, instance, name, params, from)
    {:noreply, state}
  end

  @impl true
  def handle_info({:returned_function_call, result, from}, state) do
    GenServer.reply(from, result)
    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:invoke_callback, namespace_name, import_name, context, params, token},
        %{imports: imports} = state
      ) do
    context =
      Map.merge(
        context,
        %{
          memory: WasmexWasmtime.Memory.wrap_resource(Map.get(context, :memory)),
          caller: WasmexWasmtime.StoreOrCaller.wrap_resource(Map.get(context, :caller))
        }
      )

    {success, return_value} =
      try do
        {:fn, _params, _returns, callback} =
          imports
          |> Map.get(namespace_name, %{})
          |> Map.get(import_name)

        {true, apply(callback, [context | params])}
      rescue
        e in RuntimeError -> {false, e.message}
      end

    return_values =
      case return_value do
        nil -> []
        _ -> [return_value]
      end

    :ok = WasmexWasmtime.Native.instance_receive_callback_result(token, success, return_values)
    {:noreply, state}
  end
end
