defmodule WasmexWasmtime.Wasi.WasiOptions do
  @moduledoc ~S"""
  WASI Options
  """

  alias WasmexWasmtime.Wasi.PreopenOptions
  alias WasmexWasmtime.Pipe

  defstruct [:stdin, :stdout, :stderr, args: [], env: %{}, preopen: []]

  @type t :: %__MODULE__{
          args: [String.t()],
          env: %{String.t() => String.t()},
          preopen: [PreopenOptions],
          stdin: Pipe | nil,
          stdout: Pipe | nil,
          stderr: Pipe | nil
        }
end
