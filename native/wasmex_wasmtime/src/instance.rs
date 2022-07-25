use rustler::{
    dynamic::TermType,
    env::{OwnedEnv, SavedTerm},
    resource::ResourceArc,
    types::tuple::make_tuple,
    types::ListIterator,
    Encoder, Env as RustlerEnv, Error, MapIterator, NifResult, Term,
};
use std::{sync::Mutex};
use std::thread;
use wasi_common::WasiCtx;

use wasmtime::{Engine, Instance, Linker, Store, Val, ValType, Module};

use crate::{
    atoms,
    environment::{link_imports, CallbackTokenResource},
    functions,
    module::ModuleResource,
    printable_term_type::PrintableTermType, store::{WasmexStore, StoreResource},
};

pub struct InstanceResource {
    pub inner: Mutex<Instance>,
}

#[derive(NifTuple)]
pub struct InstanceResourceResponse {
    ok: rustler::Atom,
    resource: ResourceArc<InstanceResource>,
}

// creates a new instance from the given WASM bytes
// expects the following elixir params
//
// * module (ModuleResource): the compiled WASM module
// * imports (map): a map defining eventual instance imports, may be empty if there are none.
//   structure: %{namespace_name: %{import_name: {:fn, param_types, result_types, captured_function}}}
#[rustler::nif(name = "instance_new")]
pub fn new(
    store_resource: ResourceArc<StoreResource>,
    module_resource: ResourceArc<ModuleResource>,
    imports: MapIterator,
) -> NifResult<InstanceResourceResponse> {
    let module = module_resource.inner.lock().map_err(|e| {
        rustler::Error::Term(Box::new(format!(
            "Could not unlock module resource as the mutex was poisoned: {}",
            e
        )))
    })?;
    let store: &mut WasmexStore = &mut *(store_resource.inner.lock().map_err(|e| {
        rustler::Error::Term(Box::new(format!(
            "Could not unlock store resource as the mutex was poisoned: {}",
            e
        )))
    })?);
    let engine: &Engine = &mut *(store_resource.engine.lock().map_err(|e| {
        rustler::Error::Term(Box::new(format!(
            "Could not unlock store/engine resource as the mutex was poisoned: {}",
            e
        )))
    })?);

    let store = match store {
        WasmexStore::Plain(store) => Ok(store),
        WasmexStore::Wasi(_store) => Err(Error::Term(Box::new("must pass a plain store, but got a WASI store"))),
    }?;
    let instance = link_and_create_plain_instance(store, engine, &module, imports)?;

    let resource = ResourceArc::new(InstanceResource {
        inner: Mutex::new(instance),
    });
    Ok(InstanceResourceResponse {
        ok: atoms::ok(),
        resource,
    })
}

fn link_and_create_plain_instance(store: &mut Store<()>, engine: &Engine, module: &Module, imports: MapIterator) -> Result<Instance, Error> {
    let mut linker = Linker::new(engine);
    link_imports(&mut linker, imports)?;
    linker
        .define_unknown_imports_as_traps(&module)
        .map_err(|err| Error::RaiseTerm(Box::new(err.to_string())))?;
    linker.instantiate(store, module).map_err(|err| Error::RaiseTerm(Box::new(format!("Cannot instantiate: {}", err))))
}

// Creates a new instance from the given WASM bytes.
// Expects the following elixir params:
//
// * module (ModuleResource): the compiled WASM module
// * imports (map): a map defining eventual instance imports, may be empty if there are none.
//   structure: %{namespace_name: %{import_name: {:fn, param_types, result_types, captured_function}}}
// * wasi_args (list of Strings): a list of argument strings
// * wasi_env: (map String->String): a map containing environment variable definitions, each of the type `"NAME" => "value"`
// * options: A map allowing the following keys
//   * stdin (optional): A pipe that will be passed as stdin to the WASM module
//   * stdout (optional): A pipe that will be passed as stdout to the WASM module
//   * stderr (optional): A pipe that will be passed as stderr to the WASM module
#[rustler::nif(name = "instance_new_wasi")]
pub fn new_wasi<'a>(
    store_resource: ResourceArc<StoreResource>,
    module_resource: ResourceArc<ModuleResource>,
    imports: MapIterator,
) -> NifResult<InstanceResourceResponse> {
    let module = module_resource.inner.lock().map_err(|e| {
        rustler::Error::Term(Box::new(format!(
            "Could not unlock module resource as the mutex was poisoned: {}",
            e
        )))
    })?;
    let store: &mut WasmexStore = &mut *(store_resource.inner.lock().map_err(|e| {
        rustler::Error::Term(Box::new(format!(
            "Could not unlock store resource as the mutex was poisoned: {}",
            e
        )))
    })?);
    let engine: &Engine = &mut *(store_resource.engine.lock().map_err(|e| {
        rustler::Error::Term(Box::new(format!(
            "Could not unlock store/engine resource as the mutex was poisoned: {}",
            e
        )))
    })?);

    let store = match store {
        WasmexStore::Plain(_store) => Err(Error::Term(Box::new("must pass a WASI store, but got a plain store"))),
        WasmexStore::Wasi(store) => Ok(store),
    }?;
    let instance = link_and_create_wasi_instance(store, engine, &module, imports)?;

    let resource = ResourceArc::new(InstanceResource {
        inner: Mutex::new(instance),
    });
    Ok(InstanceResourceResponse {
        ok: atoms::ok(),
        resource,
    })
}

fn link_and_create_wasi_instance(store: &mut Store<WasiCtx>, engine: &Engine, module: &Module, imports: MapIterator) -> Result<Instance, Error> {
    let mut linker: Linker<WasiCtx> = Linker::new(&engine);
    linker.allow_shadowing(true);
    linker
        .define_unknown_imports_as_traps(&module)
        .map_err(|err| Error::RaiseTerm(Box::new(err.to_string())))?;
    wasmtime_wasi::add_to_linker(&mut linker, |s| s)
        .map_err(|err| Error::RaiseTerm(Box::new(err.to_string())))?;
    link_imports(&mut linker, imports)?;
    linker.instantiate(store, module).map_err(|err| Error::RaiseTerm(Box::new(format!("Cannot instantiate: {}", err))))
}

#[rustler::nif(name = "instance_function_export_exists")]
pub fn function_export_exists(
    store_resource: ResourceArc<StoreResource>,
    instance_resource: ResourceArc<InstanceResource>,
    function_name: String,
) -> NifResult<bool> {
    let instance: Instance =
        *(instance_resource.inner.lock().map_err(|e| {
            rustler::Error::Term(Box::new(format!(
                "Could not unlock instance resource as the mutex was poisoned: {}",
                e
            )))
        })?);
    let store: &mut WasmexStore =
    &mut *(store_resource.inner.lock().map_err(|e| {
        rustler::Error::Term(Box::new(format!(
            "Could not unlock instance/store resource as the mutex was poisoned: {}",
            e
        )))
    })?);

    let result = match store {
        WasmexStore::Plain(store) => functions::exists(&instance, store, &function_name),
        WasmexStore::Wasi(store) => functions::exists(&instance, store, &function_name),
    };
    Ok(result)
}

#[rustler::nif(name = "instance_call_exported_function", schedule = "DirtyCpu")]
pub fn call_exported_function<'a>(
    env: rustler::Env<'a>,
    store_resource: ResourceArc<StoreResource>,
    instance_resource: ResourceArc<InstanceResource>,
    function_name: String,
    params: Term,
    from: Term,
) -> rustler::Atom {
    let pid = env.pid();
    // create erlang environment for the thread
    let mut thread_env = OwnedEnv::new();
    // copy over params into the thread environment
    let function_params = thread_env.save(params);
    let from = thread_env.save(from);

    thread::spawn(move || {
        thread_env.send_and_clear(&pid, |thread_env| {
            execute_function(thread_env, store_resource, instance_resource, function_name, function_params, from)
        })
    });

    atoms::ok()
}

fn execute_function(
    thread_env: RustlerEnv,
    store_resource: ResourceArc<StoreResource>,
    instance_resource: ResourceArc<InstanceResource>,
    function_name: String,
    function_params: SavedTerm,
    from: SavedTerm,
) -> Term {
    let from = from
        .load(thread_env)
        .decode::<Term>()
        .unwrap_or_else(|_| "could not load 'from' param".encode(thread_env));
    let given_params = match function_params.load(thread_env).decode::<Vec<Term>>() {
        Ok(vec) => vec,
        Err(_) => return make_error_tuple(&thread_env, "could not load 'function params'", from),
    };
    let instance: Instance =  *(instance_resource.inner.lock().unwrap());
    let mut store = store_resource.inner.lock().unwrap();
    let function_result = match &mut *store {
        WasmexStore::Plain(store) => functions::find(&instance, store, &function_name),
        WasmexStore::Wasi(store) => functions::find(&instance, store, &function_name),
    };
    let function = match function_result {
        Some(func) => func,
        None => {
            return make_error_tuple(
                &thread_env,
                &format!("exported function `{}` not found", function_name),
                from,
            )
        }
    };
    let function_params_result = match &*store {
        WasmexStore::Plain(store) => decode_function_param_terms(
            &function.ty(store).params().collect(),
            given_params,
        ),
        WasmexStore::Wasi(store) => decode_function_param_terms(
            &function.ty(store).params().collect(),
            given_params,
        ),
    };
    let function_params = match function_params_result {
        Ok(vec) => map_wasm_values_to_vals(&vec),
        Err(reason) => return make_error_tuple(&thread_env, &reason, from),
    };

    let mut results = Vec::new();
    let call_result = match &mut *store {
        WasmexStore::Plain(store) => {
            function.call(store, function_params.as_slice(), &mut results)
        }
        WasmexStore::Wasi(store) => {
            function.call(store, function_params.as_slice(), &mut results)
        }
    };
    match call_result {
        Ok(_) => (),
        Err(e) => {
            return make_error_tuple(
                &thread_env,
                &format!("Error during function excecution: `{}`.", e),
                from,
            )
        }
    };
    let mut return_values: Vec<Term> = Vec::with_capacity(results.len());
    for value in results.iter().cloned() {
        return_values.push(match value {
            Val::I32(i) => i.encode(thread_env),
            Val::I64(i) => i.encode(thread_env),
            Val::F32(i) => i.encode(thread_env),
            Val::F64(i) => i.encode(thread_env),
            // encoding V128 is not yet supported by rustler
            Val::V128(_) => {
                return make_error_tuple(&thread_env, "unable_to_return_v128_type", from)
            }
            Val::FuncRef(_) => {
                return make_error_tuple(&thread_env, "unable_to_return_func_ref_type", from)
            }
            Val::ExternRef(_) => {
                return make_error_tuple(&thread_env, "unable_to_return_extern_ref_type", from)
            }
        })
    }
    make_tuple(
        thread_env,
        &[
            atoms::returned_function_call().encode(thread_env),
            make_tuple(
                thread_env,
                &[
                    atoms::ok().encode(thread_env),
                    return_values.encode(thread_env),
                ],
            ),
            from,
        ],
    )
}

#[derive(Debug, Copy, Clone)]
pub enum WasmValue {
    I32(i32),
    I64(i64),
    F32(f32),
    F64(f64),
}

pub fn decode_function_param_terms(
    params: &Vec<ValType>,
    function_param_terms: Vec<Term>,
) -> Result<Vec<WasmValue>, String> {
    if params.len() != function_param_terms.len() {
        return Err(format!(
            "number of params does not match. expected {}, got {}",
            params.len(),
            function_param_terms.len()
        ));
    }

    let mut function_params = Vec::<WasmValue>::with_capacity(params.len());
    for (nth, (param, given_param)) in params
        .iter()
        .zip(function_param_terms.into_iter())
        .enumerate()
    {
        let value = match (param, given_param.get_type()) {
            (ValType::I32, TermType::Number) => match given_param.decode::<i32>() {
                Ok(value) => WasmValue::I32(value),
                Err(_) => {
                    return Err(format!(
                        "Cannot convert argument #{} to a WebAssembly i32 value.",
                        nth + 1
                    ));
                }
            },
            (ValType::I64, TermType::Number) => match given_param.decode::<i64>() {
                Ok(value) => WasmValue::I64(value),
                Err(_) => {
                    return Err(format!(
                        "Cannot convert argument #{} to a WebAssembly i64 value.",
                        nth + 1
                    ));
                }
            },
            (ValType::F32, TermType::Number) => match given_param.decode::<f32>() {
                Ok(value) => {
                    if value.is_finite() {
                        WasmValue::F32(value)
                    } else {
                        return Err(format!(
                            "Cannot convert argument #{} to a WebAssembly f32 value.",
                            nth + 1
                        ));
                    }
                }
                Err(_) => {
                    return Err(format!(
                        "Cannot convert argument #{} to a WebAssembly f32 value.",
                        nth + 1
                    ));
                }
            },
            (ValType::F64, TermType::Number) => match given_param.decode::<f64>() {
                Ok(value) => WasmValue::F64(value),
                Err(_) => {
                    return Err(format!(
                        "Cannot convert argument #{} to a WebAssembly f64 value.",
                        nth + 1
                    ));
                }
            },
            (_, term_type) => {
                return Err(format!(
                    "Cannot convert argument #{} to a WebAssembly value. Given `{:?}`.",
                    nth + 1,
                    PrintableTermType::PrintTerm(term_type)
                ));
            }
        };
        function_params.push(value);
    }
    Ok(function_params)
}

pub fn map_wasm_values_to_vals(values: &[WasmValue]) -> Vec<Val> {
    values
        .iter()
        .map(|value| match value {
            WasmValue::I32(value) => Val::I32(*value),
            WasmValue::I64(value) => Val::I64(*value),
            WasmValue::F32(value) => Val::F32(value.to_bits()),
            WasmValue::F64(value) => Val::F64(value.to_bits()),
        })
        .collect()
}

fn make_error_tuple<'a>(env: &RustlerEnv<'a>, reason: &str, from: Term<'a>) -> Term<'a> {
    make_tuple(
        *env,
        &[
            atoms::returned_function_call().encode(*env),
            env.error_tuple(reason),
            from,
        ],
    )
}

// called from elixir, params
// * callback_token
// * success: :ok | :error
//   indicates whether the call was successful or produced an elixir-error
// * results: [number]
//   return values of the elixir-callback - empty list when success-type is :error
#[rustler::nif(name = "instance_receive_callback_result")]
pub fn receive_callback_result(
    token_resource: ResourceArc<CallbackTokenResource>,
    success: bool,
    result_list: ListIterator,
) -> NifResult<rustler::Atom> {
    let results = if success {
        let return_types = token_resource.token.return_types.clone();
        match decode_function_param_terms(&return_types, result_list.collect()) {
            Ok(v) => v,
            Err(_reason) => {
                return Err(Error::Atom(
                    "could not convert callback result param to expected return signature",
                ));
            }
        }
    } else {
        vec![]
    };

    let mut result = token_resource.token.return_values.lock().unwrap();
    *result = Some((success, results));
    token_resource.token.continue_signal.notify_one();

    Ok(atoms::ok())
}
