defmodule WasmexWasmtime.MemoryTest do
  use ExUnit.Case, async: true
  doctest WasmexWasmtime.Memory

  defp build_wasm_instance do
    TestHelper.wasm_module()
    |> WasmexWasmtime.Instance.new(%{})
  end

  defp build_memory(size, offset) do
    {:ok, instance} = build_wasm_instance()
    WasmexWasmtime.Memory.from_instance(instance, size, offset)
  end

  describe "from_instance/1" do
    test "creates memory with defaults for size and offset" do
      {:ok, instance} = build_wasm_instance()
      {:ok, memory} = WasmexWasmtime.Memory.from_instance(instance)
      assert memory.size == :uint8
      assert memory.offset == 0
    end
  end

  describe "bytes_per_element/1" do
    test "returns number of bytes for uint8" do
      {:ok, memory} = build_memory(:uint8, 0)
      assert WasmexWasmtime.Memory.bytes_per_element(memory) == 1
    end

    test "returns number of bytes for int8" do
      {:ok, memory} = build_memory(:int8, 0)
      assert WasmexWasmtime.Memory.bytes_per_element(memory) == 1
    end

    test "returns number of bytes for uint16" do
      {:ok, memory} = build_memory(:uint16, 0)
      assert WasmexWasmtime.Memory.bytes_per_element(memory) == 2
    end

    test "returns number of bytes for int16" do
      {:ok, memory} = build_memory(:int16, 0)
      assert WasmexWasmtime.Memory.bytes_per_element(memory) == 2
    end

    test "returns number of bytes for uint32" do
      {:ok, memory} = build_memory(:uint32, 0)
      assert WasmexWasmtime.Memory.bytes_per_element(memory) == 4
    end

    test "returns number of bytes for int32" do
      {:ok, memory} = build_memory(:int32, 0)
      assert WasmexWasmtime.Memory.bytes_per_element(memory) == 4
    end
  end

  # in bytes
  @page_size 65_536
  @initial_pages 17
  # in bytes
  @min_memory_size @initial_pages * @page_size

  describe "length/1" do
    test "returns number of uint8 elements that fit into memory" do
      {:ok, memory} = build_memory(:uint8, 0)
      assert WasmexWasmtime.Memory.length(memory) == @min_memory_size
    end

    test "returns number of uint16 elements that fit into memory" do
      {:ok, memory} = build_memory(:uint16, 0)
      assert WasmexWasmtime.Memory.length(memory) == @min_memory_size / 2
    end

    test "returns number of int32 elements that fit into memory" do
      {:ok, memory} = build_memory(:int32, 0)
      assert WasmexWasmtime.Memory.length(memory) == @min_memory_size / 4
    end
  end

  describe "grow/2" do
    test "grows the memory by the given number of pages" do
      {:ok, memory} = build_memory(:uint8, 0)
      assert WasmexWasmtime.Memory.length(memory) / @page_size == @initial_pages
      assert WasmexWasmtime.Memory.grow(memory, 3) == @initial_pages
      assert WasmexWasmtime.Memory.length(memory) / @page_size == @initial_pages + 3
      assert WasmexWasmtime.Memory.grow(memory, 1) == @initial_pages + 3
      assert WasmexWasmtime.Memory.length(memory) / @page_size == @initial_pages + 4
    end
  end

  describe "get/2 and set/3" do
    test "sets and gets uint8 values" do
      {:ok, memory} = build_memory(:uint8, 0)
      assert WasmexWasmtime.Memory.get(memory, 0) == 0
      :ok = WasmexWasmtime.Memory.set(memory, 0, 42)
      assert WasmexWasmtime.Memory.get(memory, 0) == 42
    end
  end

  describe "write_binary/3" do
    test "writes a binary into memory" do
      {:ok, memory} = build_memory(:uint8, 0)
      :ok = WasmexWasmtime.Memory.write_binary(memory, 0, "hello")
      # h
      assert WasmexWasmtime.Memory.get(memory, 0) == 104
      # e
      assert WasmexWasmtime.Memory.get(memory, 1) == 101
      # l
      assert WasmexWasmtime.Memory.get(memory, 2) == 108
      # l
      assert WasmexWasmtime.Memory.get(memory, 3) == 108
      # o
      assert WasmexWasmtime.Memory.get(memory, 4) == 111

      # overwriting the same area in memory to see if the automatic null byte is being added
      :ok = WasmexWasmtime.Memory.write_binary(memory, 1, "abc")
      # not changed because of the index
      assert WasmexWasmtime.Memory.get(memory, 0) == 104
      # a
      assert WasmexWasmtime.Memory.get(memory, 1) == 97
      # b
      assert WasmexWasmtime.Memory.get(memory, 2) == 98
      # c
      assert WasmexWasmtime.Memory.get(memory, 3) == 99

      random_bytes = :crypto.strong_rand_bytes(24)
      # writing random bytes is fine as well
      :ok = WasmexWasmtime.Memory.write_binary(memory, 0, random_bytes)
      # should also be able to read it back
      assert WasmexWasmtime.Memory.read_binary(memory, 0, 24) == random_bytes
    end
  end

  describe "read_binary/3" do
    test "reads a binary from memory" do
      {:ok, memory} = build_memory(:uint8, 0)
      # h
      WasmexWasmtime.Memory.set(memory, 0, 104)
      # e
      WasmexWasmtime.Memory.set(memory, 1, 101)
      # l
      WasmexWasmtime.Memory.set(memory, 2, 108)
      # l
      WasmexWasmtime.Memory.set(memory, 3, 108)
      # o
      WasmexWasmtime.Memory.set(memory, 4, 111)

      assert WasmexWasmtime.Memory.read_binary(memory, 0, 5) == "hello"
      assert WasmexWasmtime.Memory.read_binary(memory, 3, 2) == "lo"
      assert WasmexWasmtime.Memory.read_binary(memory, 8, 0) == ""
    end
  end

  describe "read_string/3" do
    test "reads a string from memory" do
      {:ok, memory} = build_memory(:uint8, 0)
      # h
      WasmexWasmtime.Memory.set(memory, 0, 104)
      # e
      WasmexWasmtime.Memory.set(memory, 1, 101)
      # l
      WasmexWasmtime.Memory.set(memory, 2, 108)
      # l
      WasmexWasmtime.Memory.set(memory, 3, 108)
      # o
      WasmexWasmtime.Memory.set(memory, 4, 111)

      assert WasmexWasmtime.Memory.read_string(memory, 0, 5) == "hello"
      assert WasmexWasmtime.Memory.read_string(memory, 3, 2) == "lo"
      assert WasmexWasmtime.Memory.read_string(memory, 8, 0) == ""
    end
  end
end
