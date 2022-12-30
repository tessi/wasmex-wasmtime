defmodule WasmexWasmtime.Store do
  @moduledoc """
  TBD
  """

  alias WasmexWasmtime.StoreOrCaller
  alias WasmexWasmtime.Wasi.WasiOptions

  @doc """
  TBD
  """
  @spec new() :: {:error, reason :: binary()} | {:ok, StoreOrCaller.t()}
  def new() do
    case WasmexWasmtime.Native.store_new() do
      {:ok, resource} -> {:ok, StoreOrCaller.wrap_resource(resource)}
      {:error, err} -> {:error, err}
    end
  end

  @doc """
  TBD
  """
  @spec new_wasi(WasiOptions.t()) :: {:error, reason :: binary()} | {:ok, StoreOrCaller.t()}
  def new_wasi(%WasiOptions{} = options) do
    case WasmexWasmtime.Native.store_new_wasi(options) do
      {:ok, resource} -> {:ok, StoreOrCaller.wrap_resource(resource)}
      {:error, err} -> {:error, err}
    end
  end
end

defimpl Inspect, for: WasmexWasmtime.Store do
  import Inspect.Algebra

  def inspect(dict, opts) do
    concat(["#WasmexWasmtime.Store<", to_doc(dict.reference, opts), ">"])
  end
end
