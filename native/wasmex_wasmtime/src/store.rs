use rustler::{
    resource::ResourceArc, Encoder, Env as RustlerEnv, Error, ListIterator, MapIterator, NifResult,
    Term,
};
use std::sync::Mutex;
use wasi_common::WasiCtx;
use wasmtime::{Config, Engine, Store};
use wasmtime_wasi::WasiCtxBuilder;

use crate::{atoms, pipe::PipeResource};

pub enum WasmexStore {
    Plain(Store<()>),
    Wasi(Store<WasiCtx>),
}

pub struct StoreResource {
    pub inner: Mutex<WasmexStore>,
    pub engine: Mutex<Engine>,
}

#[derive(NifTuple)]
pub struct StoreResourceResponse {
    ok: rustler::Atom,
    resource: ResourceArc<StoreResource>,
}

#[rustler::nif(name = "store_new")]
pub fn new() -> NifResult<StoreResourceResponse> {
    let config = Config::new();
    let engine = Engine::new(&config).map_err(|err| Error::RaiseTerm(Box::new(err.to_string())))?;
    let store = Store::new(&engine, ());
    let resource = ResourceArc::new(StoreResource {
        inner: Mutex::new(WasmexStore::Plain(store)),
        engine: Mutex::new(engine),
    });
    Ok(StoreResourceResponse {
        ok: atoms::ok(),
        resource,
    })
}

#[rustler::nif(name = "store_new_wasi")]
pub fn new_wasi<'a>(
    env: rustler::Env<'a>,
    wasi_args: ListIterator,
    wasi_env: MapIterator,
    options: Term<'a>,
) -> NifResult<StoreResourceResponse> {
    let wasi_args = wasi_args
        .map(|term: Term| term.decode::<String>())
        .collect::<Result<Vec<String>, _>>()?;
    let wasi_env = wasi_env
        .map(|(key, val)| {
            key.decode::<String>()
                .and_then(|key| val.decode::<String>().map(|val| (key, val)))
        })
        .collect::<Result<Vec<(String, String)>, _>>()?;

    // let mut wasi_wasmer_env = create_wasi_env(wasi_args, wasi_env, options, env)?;
    let wasi_ctx_builder = WasiCtxBuilder::new()
        .args(&wasi_args)
        .map_err(|err| Error::RaiseTerm(Box::new(err.to_string())))?
        .envs(&wasi_env)
        .map_err(|err| Error::RaiseTerm(Box::new(err.to_string())))?;

    let wasi_ctx_builder = wasi_stdin(options, env, wasi_ctx_builder)?;
    let wasi_ctx_builder = wasi_stdout(options, env, wasi_ctx_builder)?;
    let wasi_ctx_builder = wasi_stderr(options, env, wasi_ctx_builder)?;
    // let wasi_ctx_builder = wasi_preopen_directories(options, env, mut wasi_ctx_builder)?; // TODO: implement this

    let config = Config::new();
    let engine = Engine::new(&config).map_err(|err| Error::RaiseTerm(Box::new(err.to_string())))?;
    let store = Store::new(&engine, wasi_ctx_builder.build());
    let resource = ResourceArc::new(StoreResource {
        inner: Mutex::new(WasmexStore::Wasi(store)),
        engine: Mutex::new(engine),
    });
    Ok(StoreResourceResponse {
        ok: atoms::ok(),
        resource,
    })
}

fn wasi_stderr(
    options: Term,
    env: RustlerEnv,
    builder: WasiCtxBuilder,
) -> Result<WasiCtxBuilder, rustler::Error> {
    if let Ok(resource) = pipe_from_wasi_options(options, "stderr", &env) {
        let pipe = resource.pipe.lock().map_err(|_e| {
            rustler::Error::Term(Box::new(
                "Could not unlock resource as the mutex was poisoned.",
            ))
        })?;
        return Ok(builder.stderr(Box::new(pipe.clone())));
    }
    Ok(builder)
}

fn wasi_stdout(
    options: Term,
    env: RustlerEnv,
    builder: WasiCtxBuilder,
) -> Result<WasiCtxBuilder, rustler::Error> {
    if let Ok(resource) = pipe_from_wasi_options(options, "stdout", &env) {
        let pipe = resource.pipe.lock().map_err(|_e| {
            rustler::Error::Term(Box::new(
                "Could not unlock resource as the mutex was poisoned.",
            ))
        })?;
        return Ok(builder.stdout(Box::new(pipe.clone())));
    }
    Ok(builder)
}

fn wasi_stdin(
    options: Term,
    env: RustlerEnv,
    builder: WasiCtxBuilder,
) -> Result<WasiCtxBuilder, rustler::Error> {
    if let Ok(resource) = pipe_from_wasi_options(options, "stdin", &env) {
        let pipe = resource.pipe.lock().map_err(|_e| {
            rustler::Error::Term(Box::new(
                "Could not unlock resource as the mutex was poisoned.",
            ))
        })?;
        return Ok(builder.stdin(Box::new(pipe.clone())));
    }
    Ok(builder)
}

fn pipe_from_wasi_options(
    options: Term,
    key: &str,
    env: &rustler::Env,
) -> Result<ResourceArc<PipeResource>, rustler::Error> {
    options
        .map_get(key.encode(*env))
        .and_then(|pipe_term| pipe_term.map_get(atoms::resource().encode(*env)))
        .and_then(|term| term.decode::<ResourceArc<PipeResource>>())
}

// fn wasi_preopen_directories<'a>(
//     options: Term<'a>,
//     env: RustlerEnv<'a>,
//     builder: &mut WasiCtxBuilder,
// ) -> Result<(), rustler::Error> {
//     if let Some(preopen) = options
//         .map_get("preopen".encode(env))
//         .ok()
//         .and_then(MapIterator::new)
//     {
//         for (key, opts) in preopen {
//             let path: &str = key.decode()?;
//             let dir =
//             builder
//                 .preopened_dir(dir, guest_path)
//                 .preopen(|builder| {
//                     let builder = builder.directory(directory);
//                     if let Ok(alias) = opts
//                         .map_get("alias".encode(env))
//                         .and_then(|term| term.decode())
//                     {
//                         builder.alias(alias);
//                     }

//                     if let Ok(flags) = opts
//                         .map_get("flags".encode(env))
//                         .and_then(|term| term.decode::<ListIterator>())
//                     {
//                         for flag in flags {
//                             if flag.eq(&atoms::read().to_term(env)) {
//                                 builder.read(true);
//                             }
//                             if flag.eq(&atoms::write().to_term(env)) {
//                                 builder.write(true);
//                             }
//                             if flag.eq(&atoms::create().to_term(env)) {
//                                 builder.create(true);
//                             }
//                         }
//                     }
//                     builder
//                 })
//                 .map_err(|e| {
//                     rustler::Error::Term(Box::new(format!("Could not create WASI state: {:?}", e)))
//                 })?;
//         }
//     }
//     Ok(())
// }
