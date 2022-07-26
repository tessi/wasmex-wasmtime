defmodule WasmexWasmtime.MemoryTest do
  use ExUnit.Case, async: true
  doctest WasmexWasmtime.Memory

  defp build_wasm_instance do
    %{store: store, module: module} = TestHelper.wasm_module()
    {:ok, instance} = WasmexWasmtime.Instance.new(store, module, %{})
    %{store: store, module: module, instance: instance}
  end

  defp build_memory() do
    %{store: store, instance: instance, module: module} = build_wasm_instance()
    {:ok, memory} = WasmexWasmtime.Memory.from_instance(store, instance)

    %{store: store, module: module, instance: instance, memory: memory}
  end

  describe "from_instance/1" do
    test "creates memory with defaults for size and offset" do
      %{store: store, instance: instance} = build_wasm_instance()
      {:ok, %WasmexWasmtime.Memory{}} = WasmexWasmtime.Memory.from_instance(store, instance)
    end
  end

  # in bytes
  @page_size 65_536
  @initial_pages 17
  # in bytes
  @min_memory_size @initial_pages * @page_size

  describe "length/1" do
    test "returns number of uint8 elements that fit into memory" do
      %{store: store, memory: memory} = build_memory()
      assert WasmexWasmtime.Memory.length(store, memory) == @min_memory_size
    end
  end

  describe "grow/2" do
    test "grows the memory by the given number of pages" do
      %{store: store, memory: memory} = build_memory()
      assert WasmexWasmtime.Memory.length(store, memory) / @page_size == @initial_pages
      assert WasmexWasmtime.Memory.grow(store, memory, 3) == @initial_pages
      assert WasmexWasmtime.Memory.length(store, memory) / @page_size == @initial_pages + 3
      assert WasmexWasmtime.Memory.grow(store, memory, 1) == @initial_pages + 3
      assert WasmexWasmtime.Memory.length(store, memory) / @page_size == @initial_pages + 4
    end
  end

  describe "get_byte/2 and set_byte/3" do
    test "sets and gets uint8 values" do
      %{store: store, memory: memory} = build_memory()
      assert WasmexWasmtime.Memory.get_byte(store, memory, 0) == 0
      :ok = WasmexWasmtime.Memory.set_byte(store, memory, 0, 42)
      assert WasmexWasmtime.Memory.get_byte(store, memory, 0) == 42
    end
  end

  describe "write_binary/3" do
    test "writes a binary into memory" do
      %{store: store, memory: memory} = build_memory()
      :ok = WasmexWasmtime.Memory.write_binary(store, memory, 0, "hello")
      # h
      assert WasmexWasmtime.Memory.get_byte(store, memory, 0) == 104
      # e
      assert WasmexWasmtime.Memory.get_byte(store, memory, 1) == 101
      # l
      assert WasmexWasmtime.Memory.get_byte(store, memory, 2) == 108
      # l
      assert WasmexWasmtime.Memory.get_byte(store, memory, 3) == 108
      # o
      assert WasmexWasmtime.Memory.get_byte(store, memory, 4) == 111

      # overwriting the same area in memory to see if the automatic null byte is being added
      :ok = WasmexWasmtime.Memory.write_binary(store, memory, 1, "abc")
      # not changed because of the index
      assert WasmexWasmtime.Memory.get_byte(store, memory, 0) == 104
      # a
      assert WasmexWasmtime.Memory.get_byte(store, memory, 1) == 97
      # b
      assert WasmexWasmtime.Memory.get_byte(store, memory, 2) == 98
      # c
      assert WasmexWasmtime.Memory.get_byte(store, memory, 3) == 99

      random_bytes = :crypto.strong_rand_bytes(24)
      # writing random bytes is fine as well
      :ok = WasmexWasmtime.Memory.write_binary(store, memory, 0, random_bytes)
      # should also be able to read it back
      assert WasmexWasmtime.Memory.read_binary(store, memory, 0, 24) == random_bytes
    end
  end

  describe "read_binary/3" do
    test "reads a binary from memory" do
      %{store: store, memory: memory} = build_memory()
      # h
      WasmexWasmtime.Memory.set_byte(store, memory, 0, 104)
      # e
      WasmexWasmtime.Memory.set_byte(store, memory, 1, 101)
      # l
      WasmexWasmtime.Memory.set_byte(store, memory, 2, 108)
      # l
      WasmexWasmtime.Memory.set_byte(store, memory, 3, 108)
      # o
      WasmexWasmtime.Memory.set_byte(store, memory, 4, 111)

      assert WasmexWasmtime.Memory.read_binary(store, memory, 0, 5) == "hello"
      assert WasmexWasmtime.Memory.read_binary(store, memory, 3, 2) == "lo"
      assert WasmexWasmtime.Memory.read_binary(store, memory, 8, 0) == ""
    end
  end

  describe "read_string/3" do
    test "reads a string from memory" do
      %{store: store, memory: memory} = build_memory()
      # h
      WasmexWasmtime.Memory.set_byte(store, memory, 0, 104)
      # e
      WasmexWasmtime.Memory.set_byte(store, memory, 1, 101)
      # l
      WasmexWasmtime.Memory.set_byte(store, memory, 2, 108)
      # l
      WasmexWasmtime.Memory.set_byte(store, memory, 3, 108)
      # o
      WasmexWasmtime.Memory.set_byte(store, memory, 4, 111)

      assert WasmexWasmtime.Memory.read_string(store, memory, 0, 5) == "hello"
      assert WasmexWasmtime.Memory.read_string(store, memory, 3, 2) == "lo"
      assert WasmexWasmtime.Memory.read_string(store, memory, 8, 0) == ""
    end
  end
end
