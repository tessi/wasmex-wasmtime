defmodule WasmexWasmtime.Store do
  @moduledoc """
  TBD
  """

  alias WasmexWasmtime.StoreOrCaller

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
  @spec new_wasi(%{
          optional(:args) => [String.t()],
          optional(:env) => %{String.t() => String.t()},
          optional(:stdin) => WasmexWasmtime.Pipe.t(),
          optional(:stdout) => WasmexWasmtime.Pipe.t(),
          optional(:stderr) => WasmexWasmtime.Pipe.t()
        }) :: {:error, reason :: binary()} | {:ok, StoreOrCaller.t()}
  def new_wasi(wasi) when is_map(wasi) do
    args = Map.get(wasi, "args", [])
    env = Map.get(wasi, "env", %{})
    {opts, _} = Map.split(wasi, ["stdin", "stdout", "stderr", "preopen"])

    case WasmexWasmtime.Native.store_new_wasi(args, env, opts) do
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
