defmodule WasmexWasmtime.PipeTest do
  use ExUnit.Case, async: true
  doctest WasmexWasmtime.Pipe

  defp build_pipe(_) do
    {:ok, pipe} = WasmexWasmtime.Pipe.create()
    %{pipe: pipe}
  end

  describe "size/1 && set_len/2" do
    setup :build_pipe

    test "returns the pipes size and allowes resizing", %{pipe: pipe} do
      assert WasmexWasmtime.Pipe.size(pipe) == 0
      WasmexWasmtime.Pipe.set_len(pipe, 42)
      assert WasmexWasmtime.Pipe.size(pipe) == 42
    end
  end

  describe "read/1 && write/2" do
    setup :build_pipe

    test "allows reads and writes", %{pipe: pipe} do
      assert WasmexWasmtime.Pipe.read(pipe) == ""
      assert {:ok, 13} == WasmexWasmtime.Pipe.write(pipe, "Hello, World!")
      assert WasmexWasmtime.Pipe.read(pipe) == "Hello, World!"
    end
  end
end
