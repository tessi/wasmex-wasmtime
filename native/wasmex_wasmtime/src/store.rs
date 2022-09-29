use rustler::{
    resource::ResourceArc, Encoder, Env as RustlerEnv, Error, ListIterator, MapIterator, NifResult,
    Term,
};
use std::sync::Mutex;
use wasi_common::WasiCtx;
use wasmtime::{Config, Engine, Store};
use wasmtime_wasi::WasiCtxBuilder;

use crate::{
    atoms,
    environment::{StoreOrCaller, StoreOrCallerResource, StoreOrCallerResourceResponse},
    pipe::{Pipe, PipeResource},
};

pub struct StoreData {
    pub(crate) wasi: Option<WasiCtx>,
}

#[rustler::nif(name = "store_new")]
pub fn new() -> NifResult<StoreOrCallerResourceResponse> {
    let config = Config::new();
    let engine = Engine::new(&config).map_err(|err| Error::Term(Box::new(err.to_string())))?;
    let store = Store::new(&engine, StoreData { wasi: None });
    let resource = ResourceArc::new(StoreOrCallerResource {
        inner: Mutex::new(StoreOrCaller::Store(store)),
    });
    Ok(StoreOrCallerResourceResponse {
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
) -> NifResult<StoreOrCallerResourceResponse> {
    let wasi_args = wasi_args
        .map(|term: Term| term.decode::<String>())
        .collect::<Result<Vec<String>, _>>()?;
    let wasi_env = wasi_env
        .map(|(key, val)| {
            key.decode::<String>()
                .and_then(|key| val.decode::<String>().map(|val| (key, val)))
        })
        .collect::<Result<Vec<(String, String)>, _>>()?;

    let wasi_ctx_builder = WasiCtxBuilder::new()
        .args(&wasi_args)
        .map_err(|err| Error::Term(Box::new(err.to_string())))?
        .envs(&wasi_env)
        .map_err(|err| Error::Term(Box::new(err.to_string())))?;

    let wasi_ctx_builder = wasi_stdin(options, env, wasi_ctx_builder)?;
    let wasi_ctx_builder = wasi_stdout(options, env, wasi_ctx_builder)?;
    let wasi_ctx_builder = wasi_stderr(options, env, wasi_ctx_builder)?;
    let wasi_ctx_builder = wasi_preopen_directories(options, env, wasi_ctx_builder)?;
    let wasi_ctx = wasi_ctx_builder.build();

    let config = Config::new();
    let engine = Engine::new(&config).map_err(|err| Error::Term(Box::new(err.to_string())))?;
    let store = Store::new(
        &engine,
        StoreData {
            wasi: Some(wasi_ctx),
        },
    );
    let resource = ResourceArc::new(StoreOrCallerResource {
        inner: Mutex::new(StoreOrCaller::Store(store)),
    });
    Ok(StoreOrCallerResourceResponse {
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
        let pipe: &Pipe = &*(resource.pipe.lock().map_err(|_e| {
            rustler::Error::Term(Box::new(
                "Could not unlock resource as the mutex was poisoned.",
            ))
        })?);
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

fn wasi_preopen_directories<'a>(
    options: Term<'a>,
    env: RustlerEnv<'a>,
    builder: WasiCtxBuilder,
) -> Result<WasiCtxBuilder, rustler::Error> {
    let builder = if let Some(preopen) = options
        .map_get("preopen".encode(env))
        .ok()
        .and_then(MapIterator::new)
    {
        preopen.fold(Ok(builder), |builder, dir_opts| {
            preopen_directory(&env, builder, dir_opts)
        })?
    } else {
        builder
    };
    Ok(builder)
}

fn preopen_directory(
    env: &RustlerEnv,
    builder: Result<WasiCtxBuilder, Error>,
    (key, opts): (Term, Term),
) -> Result<WasiCtxBuilder, Error> {
    let builder = builder?;
    let path: &str = key.decode()?;
    let dir = Dir::from_std_file(
        std::fs::File::open(path).map_err(|err| rustler::Error::Term(Box::new(err.to_string())))?,
    );
    let guest_path = if let Ok(alias) = opts
        .map_get("alias".encode(*env))
        .and_then(|term| term.decode())
    {
        alias
    } else {
        path
    };
    let builder = builder
        .preopened_dir(dir, guest_path)
        .map_err(|err| Error::Term(Box::new(err.to_string())))?;
    Ok(builder)
}
