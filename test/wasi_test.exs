defmodule WasiTest do
  use ExUnit.Case, async: true
  doctest WasmexWasmtime

  alias WasmexWasmtime.Wasi.PreopenOptions
  alias WasmexWasmtime.Wasi.WasiOptions

  def tmp_file_path(suffix) do
    dir = System.tmp_dir!()

    now =
      DateTime.utc_now()
      |> DateTime.to_iso8601()
      |> String.replace(~r{[:.]}, "_")

    rand = to_string(:rand.uniform(1000))
    filename = "wasi_test_#{now}_#{rand}_#{suffix}.tmp"
    {dir, filename, Path.join(dir, filename)}
  end

  test "running a WASM/WASI module while overriding some WASI methods" do
    imports = %{
      wasi_snapshot_preview1: %{
        clock_time_get:
          {:fn, [:i32, :i64, :i32], [:i32],
           fn %{memory: memory, caller: caller}, _clock_id, _precision, time_ptr ->
             # writes a time struct into memory representing 42 seconds since the epoch

             # 64-bit tv_sec
             WasmexWasmtime.Memory.set_byte(caller, memory, time_ptr + 0, 0)
             WasmexWasmtime.Memory.set_byte(caller, memory, time_ptr + 1, 0)
             WasmexWasmtime.Memory.set_byte(caller, memory, time_ptr + 2, 0)
             WasmexWasmtime.Memory.set_byte(caller, memory, time_ptr + 3, 0)
             WasmexWasmtime.Memory.set_byte(caller, memory, time_ptr + 4, 10)
             WasmexWasmtime.Memory.set_byte(caller, memory, time_ptr + 5, 0)
             WasmexWasmtime.Memory.set_byte(caller, memory, time_ptr + 6, 0)
             WasmexWasmtime.Memory.set_byte(caller, memory, time_ptr + 7, 0)

             # 64-bit n_sec
             WasmexWasmtime.Memory.set_byte(caller, memory, time_ptr + 8, 0)
             WasmexWasmtime.Memory.set_byte(caller, memory, time_ptr + 9, 0)
             WasmexWasmtime.Memory.set_byte(caller, memory, time_ptr + 10, 0)
             WasmexWasmtime.Memory.set_byte(caller, memory, time_ptr + 11, 0)
             WasmexWasmtime.Memory.set_byte(caller, memory, time_ptr + 12, 0)
             WasmexWasmtime.Memory.set_byte(caller, memory, time_ptr + 13, 0)
             WasmexWasmtime.Memory.set_byte(caller, memory, time_ptr + 14, 0)
             WasmexWasmtime.Memory.set_byte(caller, memory, time_ptr + 15, 0)

             0
           end},
        random_get:
          {:fn, [:i32, :i32], [:i32],
           fn %{memory: memory, caller: caller}, address, size ->
             Enum.each(0..size, fn index ->
               WasmexWasmtime.Memory.set_byte(caller, memory, address + index, 0)
             end)

             # randomly selected `4` with a fair dice roll
             WasmexWasmtime.Memory.set_byte(caller, memory, address, 4)

             0
           end}
      }
    }

    {:ok, pipe} = WasmexWasmtime.Pipe.create()

    wasi = %WasiOptions{
      args: ["hello", "from elixir"],
      env: %{
        "A_NAME_MAPS" => "to a value",
        "THE_TEST_WASI_FILE" => "prints all environment variables"
      },
      stdin: pipe,
      stdout: pipe,
      stderr: pipe
    }

    instance =
      start_supervised!(
        {WasmexWasmtime,
         %{bytes: File.read!(TestHelper.wasi_test_file_path()), imports: imports, wasi: wasi}}
      )

    {:ok, _} = WasmexWasmtime.call_function(instance, :_start, [])

    WasmexWasmtime.Pipe.seek(pipe, 0)

    assert WasmexWasmtime.Pipe.read(pipe) ==
             """
             Hello from the WASI test program!

             Arguments:
             hello
             from elixir

             Environment:
             A_NAME_MAPS=to a value
             THE_TEST_WASI_FILE=prints all environment variables

             Current Time (Since Unix Epoch):
             42

             Random Number: 4

             """
  end

  test "file system access without preopened dirs" do
    {:ok, stdout} = WasmexWasmtime.Pipe.create()
    wasi = %WasiOptions{args: ["wasmex_wasmtime", "list_files", "src"], stdout: stdout}

    instance =
      start_supervised!(
        {WasmexWasmtime, %{bytes: File.read!(TestHelper.wasi_test_file_path()), wasi: wasi}}
      )

    {:ok, _} = WasmexWasmtime.call_function(instance, :_start, [])
    WasmexWasmtime.Pipe.seek(stdout, 0)
    assert WasmexWasmtime.Pipe.read(stdout) == "Could not find directory src\n"
  end

  test "list files on a preopened dir with all permissions" do
    {:ok, stdout} = WasmexWasmtime.Pipe.create()

    wasi = %WasiOptions{
      args: ["wasmex_wasmtime", "list_files", "test/wasi_test/src"],
      stdout: stdout,
      preopen: [%PreopenOptions{path: "test/wasi_test/src"}]
    }

    instance =
      start_supervised!(
        {WasmexWasmtime, %{bytes: File.read!(TestHelper.wasi_test_file_path()), wasi: wasi}}
      )

    {:ok, _} = WasmexWasmtime.call_function(instance, :_start, [])
    WasmexWasmtime.Pipe.seek(stdout, 0)
    assert WasmexWasmtime.Pipe.read(stdout) == "\"test/wasi_test/src/main.rs\"\n"
  end

  test "list files on a preopened dir with alias" do
    {:ok, stdout} = WasmexWasmtime.Pipe.create()

    wasi = %WasiOptions{
      args: ["wasmex_wasmtime", "list_files", "aliased_src"],
      stdout: stdout,
      preopen: [%PreopenOptions{path: "test/wasi_test/src", alias: "aliased_src"}]
    }

    instance =
      start_supervised!(
        {WasmexWasmtime, %{bytes: File.read!(TestHelper.wasi_test_file_path()), wasi: wasi}}
      )

    {:ok, _} = WasmexWasmtime.call_function(instance, :_start, [])
    WasmexWasmtime.Pipe.seek(stdout, 0)
    assert WasmexWasmtime.Pipe.read(stdout) == "\"aliased_src/main.rs\"\n"
  end

  test "read a file on a preopened dir" do
    {:ok, stdout} = WasmexWasmtime.Pipe.create()

    wasi = %WasiOptions{
      args: ["wasmex_wasmtime", "read_file", "src/main.rs"],
      stdout: stdout,
      preopen: [%PreopenOptions{path: "test/wasi_test/src", alias: "src"}]
    }

    instance =
      start_supervised!(
        {WasmexWasmtime, %{bytes: File.read!(TestHelper.wasi_test_file_path()), wasi: wasi}}
      )

    {:ok, _} = WasmexWasmtime.call_function(instance, :_start, [])
    {:ok, expected_content} = File.read("test/wasi_test/src/main.rs")
    WasmexWasmtime.Pipe.seek(stdout, 0)
    assert WasmexWasmtime.Pipe.read(stdout) == expected_content <> "\n"
  end

  test "write a file on a preopened dir" do
    {dir, filename, filepath} = tmp_file_path("write_file")
    File.write!(filepath, "existing content\n")

    {:ok, stdout} = WasmexWasmtime.Pipe.create()

    wasi = %WasiOptions{
      args: ["wasmex_wasmtime", "write_file", "src/#{filename}"],
      stdout: stdout,
      preopen: [%PreopenOptions{path: dir, alias: "src"}]
    }

    instance =
      start_supervised!(
        {WasmexWasmtime, %{bytes: File.read!(TestHelper.wasi_test_file_path()), wasi: wasi}}
      )

    {:ok, _} = WasmexWasmtime.call_function(instance, :_start, [])

    WasmexWasmtime.Pipe.seek(stdout, 0)
    assert WasmexWasmtime.Pipe.read(stdout) == ""

    {:ok, file_contents} = File.read(filepath)
    assert "Hello, updated world!" == file_contents

    File.rm!(filepath)
  end

  test "create a file on a preopened dir" do
    {dir, filename, filepath} = tmp_file_path("create_file")

    {:ok, stdout} = WasmexWasmtime.Pipe.create()

    wasi = %WasiOptions{
      args: ["wasmex_wasmtime", "create_file", "src/#{filename}"],
      stdout: stdout,
      preopen: [%PreopenOptions{path: dir, alias: "src"}]
    }

    instance =
      start_supervised!(
        {WasmexWasmtime, %{bytes: File.read!(TestHelper.wasi_test_file_path()), wasi: wasi}}
      )

    {:ok, _} = WasmexWasmtime.call_function(instance, :_start, [])

    {:ok, file_contents} = File.read(filepath)
    assert "Hello, created world!" == file_contents

    WasmexWasmtime.Pipe.seek(stdout, 0)
    assert WasmexWasmtime.Pipe.read(stdout) == ""
    File.rm!(filepath)
  end
end
