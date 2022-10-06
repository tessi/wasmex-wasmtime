defmodule WasmexWasmtime.Instance do
  @moduledoc """
  Instantiates a WebAssembly module and allows calling exported functions on it.

      # Read a WASM file and compile it into a WASM module
      {:ok, bytes } = File.read("wasmex_wasmtime_test.wasm")
      {:ok, module} = WasmexWasmtime.Module.compile(bytes)

      # Instantiates the WASM module.
      {:ok, instance } = WasmexWasmtime.start_link(%{module: module})

      # Call a function on it.
      {:ok, [result]} = WasmexWasmtime.call_function(instance, "sum", [1, 2])

      IO.puts result # 3

  All exported functions are accessible via `call_exported_function`.
  Arguments of these functions are automatically casted to WebAssembly values.
  Note that WebAssembly only knows number datatypes (floats and integers of various sizes).

  You can pass arbitrary data to WebAssembly by writing data into an instances memory. The `memory/3` function returns a `WasmexWasmtime.Memory` struct representing the memory of an instance, e.g.:

  ```elixir
  {:ok, memory} = WasmexWasmtime.Instance.memory(instance, :uint8, 0)
  ```

  This module, especially `call_exported_function/4`, is assumed to be called within a GenServer context.
  Usually, functions definedd here are called through the `WasmexWasmtime` module API to satisfy this assumption.
  """

  @type t :: %__MODULE__{
          resource: binary(),
          reference: reference()
        }

  defstruct resource: nil,
            # The actual NIF instance resource.
            # Normally the compiler will happily do stuff like inlining the
            # resource in attributes. This will convert the resource into an
            # empty binary with no warning. This will make that harder to
            # accidentally do.
            reference: nil

  @spec new(WasmexWasmtime.StoreOrCaller.t(), WasmexWasmtime.Module.t(), %{
          optional(binary()) => (... -> any())
        }) ::
          {:ok, __MODULE__.t()} | {:error, binary()}
  def new(store_or_caller, module, imports) when is_map(imports) do
    %WasmexWasmtime.StoreOrCaller{resource: store_or_caller_resource} = store_or_caller
    %WasmexWasmtime.Module{resource: module_resource} = module

    case WasmexWasmtime.Native.instance_new(store_or_caller_resource, module_resource, imports) do
      {:ok, resource} -> {:ok, wrap_resource(resource)}
      {:error, err} -> {:error, err}
    end
  end

  defp wrap_resource(resource) do
    %__MODULE__{
      resource: resource,
      reference: make_ref()
    }
  end

  @spec function_export_exists(WasmexWasmtime.StoreOrCaller.t(), __MODULE__.t(), binary()) ::
          boolean()
  def function_export_exists(store_or_caller, instance, name) when is_binary(name) do
    %WasmexWasmtime.StoreOrCaller{resource: store_or_caller_resource} = store_or_caller
    %__MODULE__{resource: instance_resource} = instance

    WasmexWasmtime.Native.instance_function_export_exists(
      store_or_caller_resource,
      instance_resource,
      name
    )
  end

  @doc """
  Calls a function with the given `name` and `params` on the WebAssembly `instance`.
  This function assumes to be called within a GenServer context, it expects a `from` argument
  as given by `handle_call` etc.

  The WebAssembly function will be invoked asynchronously in a new OS thread.
  The calling process will receive a `{:returned_function_call, result, from}` message once
  the execution finished.
  The result either is an `{:error, reason}` or the `:ok` atom.

  A BadArg exception may be thrown when given unexpected input data.
  """
  @spec call_exported_function(
          WasmexWasmtime.StoreOrCaller.t(),
          __MODULE__.t(),
          binary(),
          [any()],
          GenServer.from()
        ) ::
          :ok | {:error, binary()}
  def call_exported_function(store_or_caller, instance, name, params, from)
      when is_binary(name) do
    %{resource: store_or_caller_resource} = store_or_caller
    %__MODULE__{resource: instance_resource} = instance

    WasmexWasmtime.Native.instance_call_exported_function(
      store_or_caller_resource,
      instance_resource,
      name,
      params,
      from
    )
  end

  @spec memory(WasmexWasmtime.StoreOrCaller.t(), __MODULE__.t()) ::
          {:ok, WasmexWasmtime.Memory.t()} | {:error, binary()}
  def memory(store, instance) do
    WasmexWasmtime.Memory.from_instance(store, instance)
  end
end

defimpl Inspect, for: WasmexWasmtime.Instance do
  import Inspect.Algebra

  def inspect(dict, opts) do
    concat(["#WasmexWasmtime.Instance<", to_doc(dict.reference, opts), ">"])
  end
end
