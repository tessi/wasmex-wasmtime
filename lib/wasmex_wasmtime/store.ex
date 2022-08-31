defmodule WasmexWasmtime.Store do
  @moduledoc """
  TBD
  """

  alias WasmexWasmtime.StoreOrCaller

  @type t :: %__MODULE__{
          resource: binary(),
          reference: reference()
        }

  defstruct resource: nil,
            # The actual NIF store resource.
            # Normally the compiler will happily do stuff like inlining the
            # resource in attributes. This will convert the resource into an
            # empty binary with no warning. This will make that harder to
            # accidentally do.
            reference: nil

  def wrap_resource(resource) do
    %__MODULE__{
      resource: resource,
      reference: make_ref()
    }
  end

  @doc """
  TBD
  """
  @spec new() :: {:error, reason :: binary()} | {:ok, __MODULE__.t()}
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
        }) :: {:error, reason :: binary()} | {:ok, __MODULE__.t()}
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
