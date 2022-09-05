defmodule WasmexWasmtime.Native do
  @moduledoc false

  mix_config = Mix.Project.config()
  version = mix_config[:version]
  github_url = mix_config[:package][:links]["GitHub"]

  use RustlerPrecompiled,
    otp_app: :wasmex_wasmtime,
    base_url: "#{github_url}/releases/download/v#{version}",
    version: version,
    force_build: System.get_env("WASMEX_WASMTIME_BUILD") in ["1", "true"]

  def module_compile(_store_or_caller_resource, _bytes), do: error()
  def module_exports(_module_resource), do: error()
  def module_imports(_module_resource), do: error()
  def module_name(_module_resource), do: error()
  def module_serialize(_module_resource), do: error()
  def module_unsafe_deserialize(_binary), do: error()

  def instance_new(_store_or_caller_resource, _module_resource, _imports), do: error()

  def instance_function_export_exists(
        _store_or_caller_resource,
        _instance_resource,
        _function_name
      ),
      do: error()

  def instance_receive_callback_result(_callback_token, _success, _params), do: error()

  def instance_call_exported_function(
        _store_or_caller_resource,
        _instance_resource,
        _function_name,
        _params,
        _from
      ),
      do: error()

  def memory_from_instance(_store_resource, _memory_resource), do: error()
  def memory_bytes_per_element(_size), do: error()
  def memory_length(_store_resource, _memory_resource), do: error()
  def memory_grow(_store_resource, _memory_resource, _pages), do: error()
  def memory_get_byte(_store_or_caller_resource, _memory_resource, _index), do: error()
  def memory_set_byte(_store_or_caller_resource, _memory_resource, _index, _value), do: error()
  def memory_read_binary(_store_resource, _memory_resource, _index, _length), do: error()
  def memory_write_binary(_store_resource, _memory_resource, _index, _binary), do: error()

  def pipe_create(), do: error()
  def pipe_size(_pipe_resource), do: error()
  def pipe_seek(_pipe_resource, _pos_from_start), do: error()
  def pipe_read_binary(_pipe_resource), do: error()
  def pipe_write_binary(_pipe_resource, _binary), do: error()

  def store_new(), do: error()
  def store_new_wasi(_args, _env, _opts), do: error()

  # When the NIF is loaded, it will override functions in this module.
  # Calling error is handles the case when the nif could not be loaded.
  defp error, do: :erlang.nif_error(:nif_not_loaded)
end
