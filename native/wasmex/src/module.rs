use rustler::{
    resource::ResourceArc,
    types::{binary::Binary, tuple::make_tuple},
    Atom, NifResult, OwnedBinary, Term,
};
use std::{collections::HashMap, sync::Mutex};

use wasmtime::{Engine, ExternType, FuncType, GlobalType, MemoryType, Module, TableType};

use crate::atoms;

pub struct ModuleResource {
    pub module: Mutex<Module>,
}

#[derive(NifTuple)]
pub struct ModuleResourceResponse {
    ok: rustler::Atom,
    resource: ResourceArc<ModuleResource>,
}

#[rustler::nif(name = "module_compile")]
pub fn compile(binary: Binary) -> NifResult<ModuleResourceResponse> {
    let bytes = binary.as_slice();
    let engine = Engine::default();
    match Module::new(&engine, bytes) {
        Ok(module) => {
            let resource = ResourceArc::new(ModuleResource {
                module: Mutex::new(module),
            });
            Ok(ModuleResourceResponse {
                ok: atoms::ok(),
                resource,
            })
        }
        Err(e) => Err(rustler::Error::Term(Box::new(format!(
            "Could not compile module: {:?}",
            e
        )))),
    }
}

#[rustler::nif(name = "module_name")]
pub fn name(resource: ResourceArc<ModuleResource>) -> NifResult<String> {
    let module: std::sync::MutexGuard<'_, Module> = resource.module.lock().map_err(|e| {
        rustler::Error::Term(Box::new(format!(
            "Could not unlock module resource as the mutex was poisoned: {}",
            e
        )))
    })?;
    let name = module
        .name()
        .ok_or_else(|| rustler::Error::Term(Box::new("no module name set")))?;
    Ok(name.into())
}

#[rustler::nif(name = "module_set_name")]
pub fn set_name(resource: ResourceArc<ModuleResource>, new_name: String) -> NifResult<Atom> {
    Err(rustler::Error::Term(Box::new("not supported")))
}

#[rustler::nif(name = "module_exports")]
pub fn exports(env: rustler::Env, resource: ResourceArc<ModuleResource>) -> NifResult<Term> {
    let module: std::sync::MutexGuard<'_, Module> = resource.module.lock().map_err(|e| {
        rustler::Error::Term(Box::new(format!(
            "Could not unlock module resource as the mutex was poisoned: {}",
            e
        )))
    })?;
    let mut map = rustler::Term::map_new(env);
    for export in module.exports() {
        let export_name = rustler::Encoder::encode(export.name(), env);
        let export_info = match export.ty() {
            ExternType::Func(f) => function_info(env, &f),
            ExternType::Global(g) => global_info(env, &g),
            ExternType::Table(t) => table_info(env, &t),
            ExternType::Memory(m) => memory_info(env, &m),
        };
        map = map.map_put(export_name, export_info)?;
    }
    Ok(map)
}

#[rustler::nif(name = "module_imports")]
pub fn imports(env: rustler::Env, resource: ResourceArc<ModuleResource>) -> NifResult<Term> {
    let module: std::sync::MutexGuard<'_, Module> = resource.module.lock().map_err(|e| {
        rustler::Error::Term(Box::new(format!(
            "Could not unlock module resource as the mutex was poisoned: {}",
            e
        )))
    })?;
    let mut namespaces = HashMap::new();
    for import in module.imports() {
        let import_name = rustler::Encoder::encode(&import.name().ok_or(""), env);
        let import_module = String::from(import.module());

        let import_info = match import.ty() {
            ExternType::Func(f) => function_info(env, &f),
            ExternType::Global(g) => global_info(env, &g),
            ExternType::Table(t) => table_info(env, &t),
            ExternType::Memory(m) => memory_info(env, &m),
        };
        let map = namespaces
            .entry(import_module)
            .or_insert_with(|| rustler::Term::map_new(env));
        *map = map.map_put(import_name, import_info)?;
    }
    let mut map = rustler::Term::map_new(env);
    for (module_name, &module_map) in &namespaces {
        let module_name = rustler::Encoder::encode(&module_name, env);
        map = map.map_put(module_name, module_map)?;
    }
    Ok(map)
}

fn function_info<'a>(env: rustler::Env<'a>, function_type: &FuncType) -> Term<'a> {
    let params =
        function_type.params().fold(
            Term::list_new_empty(env),
            |acc, param_type| match param_type {
                wasmtime::ValType::I32 => acc.list_prepend(atoms::i32().to_term(env)),
                wasmtime::ValType::I64 => acc.list_prepend(atoms::i64().to_term(env)),
                wasmtime::ValType::F32 => acc.list_prepend(atoms::f32().to_term(env)),
                wasmtime::ValType::F64 => acc.list_prepend(atoms::f64().to_term(env)),
                wasmtime::ValType::V128 => acc.list_prepend(atoms::v128().to_term(env)),
                wasmtime::ValType::ExternRef => acc.list_prepend(atoms::extern_ref().to_term(env)),
                wasmtime::ValType::FuncRef => acc.list_prepend(atoms::func_ref().to_term(env)),
            },
        );
    let params = params
        .list_reverse()
        .expect("cannot fail, its always a list");
    let results =
        function_type.results().fold(
            Term::list_new_empty(env),
            |acc, param_type| match param_type {
                wasmtime::ValType::I32 => acc.list_prepend(atoms::i32().to_term(env)),
                wasmtime::ValType::I64 => acc.list_prepend(atoms::i64().to_term(env)),
                wasmtime::ValType::F32 => acc.list_prepend(atoms::f32().to_term(env)),
                wasmtime::ValType::F64 => acc.list_prepend(atoms::f64().to_term(env)),
                wasmtime::ValType::V128 => acc.list_prepend(atoms::v128().to_term(env)),
                wasmtime::ValType::ExternRef => acc.list_prepend(atoms::extern_ref().to_term(env)),
                wasmtime::ValType::FuncRef => acc.list_prepend(atoms::func_ref().to_term(env)),
            },
        );
    let results = results
        .list_reverse()
        .expect("cannot fail, its always a list");
    let terms = vec![atoms::__fn__().to_term(env), params, results];
    make_tuple(env, &terms)
}

fn global_info<'a>(env: rustler::Env<'a>, global_type: &GlobalType) -> Term<'a> {
    let mut map = rustler::Term::map_new(env);
    match global_type.mutability() {
        wasmtime::Mutability::Const => {
            map = map
                .map_put(
                    atoms::mutability().to_term(env),
                    atoms::__const__().to_term(env),
                )
                .expect("cannot fail; is always a map")
        }
        wasmtime::Mutability::Var => {
            map = map
                .map_put(atoms::mutability().to_term(env), atoms::var().to_term(env))
                .expect("cannot fail; is always a map")
        }
    }
    let ty = match global_type.content() {
        wasmtime::ValType::I32 => atoms::i32().to_term(env),
        wasmtime::ValType::I64 => atoms::i64().to_term(env),
        wasmtime::ValType::F32 => atoms::f32().to_term(env),
        wasmtime::ValType::F64 => atoms::f64().to_term(env),
        wasmtime::ValType::V128 => atoms::v128().to_term(env),
        wasmtime::ValType::ExternRef => atoms::extern_ref().to_term(env),
        wasmtime::ValType::FuncRef => atoms::func_ref().to_term(env),
    };
    map = map
        .map_put(atoms::__type__().to_term(env), ty)
        .expect("cannot fail; is always a map");
    let terms = vec![atoms::global().to_term(env), map];
    make_tuple(env, &terms)
}

fn table_info<'a>(env: rustler::Env<'a>, table_type: &TableType) -> Term<'a> {
    let mut map = rustler::Term::map_new(env);
    if let Some(i) = table_type.maximum() {
        map = map
            .map_put(
                atoms::maximum().to_term(env),
                rustler::Encoder::encode(&i, env),
            )
            .expect("cannot fail; is always a map");
    }
    map = map
        .map_put(
            atoms::minimum().to_term(env),
            rustler::Encoder::encode(&table_type.minimum(), env),
        )
        .expect("cannot fail; is always a map");
    let ty = match table_type.element() {
        wasmtime::ValType::I32 => atoms::i32().to_term(env),
        wasmtime::ValType::I64 => atoms::i64().to_term(env),
        wasmtime::ValType::F32 => atoms::f32().to_term(env),
        wasmtime::ValType::F64 => atoms::f64().to_term(env),
        wasmtime::ValType::V128 => atoms::v128().to_term(env),
        wasmtime::ValType::ExternRef => atoms::extern_ref().to_term(env),
        wasmtime::ValType::FuncRef => atoms::func_ref().to_term(env),
    };
    map = map
        .map_put(atoms::__type__().to_term(env), ty)
        .expect("cannot fail; is always a map");
    let terms = vec![atoms::table().to_term(env), map];
    make_tuple(env, &terms)
}

fn memory_info<'a>(env: rustler::Env<'a>, memory_type: &MemoryType) -> Term<'a> {
    let mut map = rustler::Term::map_new(env);
    if let Some(pages) = memory_type.maximum() {
        map = map
            .map_put(
                atoms::maximum().to_term(env),
                rustler::Encoder::encode(&pages, env),
            )
            .expect("cannot fail; is always a map");
    }
    map = map
        .map_put(
            atoms::minimum().to_term(env),
            rustler::Encoder::encode(&memory_type.minimum(), env),
        )
        .expect("cannot fail; is always a map");
    map = map
        .map_put(
            atoms::shared().to_term(env),
            rustler::Encoder::encode(&false, env), // TODO: need to contribute is_shared on wasmtie
        )
        .expect("cannot fail; is always a map");
    let terms: Vec<Term> = vec![atoms::memory().to_term(env), map];
    make_tuple(env, &terms)
}

#[rustler::nif(name = "module_serialize")]
pub fn serialize(env: rustler::Env, resource: ResourceArc<ModuleResource>) -> NifResult<Binary> {
    let module: std::sync::MutexGuard<'_, Module> = resource.module.lock().map_err(|e| {
        rustler::Error::Term(Box::new(format!(
            "Could not unlock module resource as the mutex was poisoned: {}",
            e
        )))
    })?;
    let serialized_module: Vec<u8> = module.serialize().map_err(|e| {
        rustler::Error::Term(Box::new(format!("Could not serialize module: {}", e)))
    })?;
    let mut binary = OwnedBinary::new(serialized_module.len())
        .ok_or_else(|| rustler::Error::Term(Box::new("not enough memory")))?;
    binary.copy_from_slice(&serialized_module);
    Ok(binary.release(env))
}

#[rustler::nif(name = "module_unsafe_deserialize")]
pub fn unsafe_deserialize(binary: Binary) -> NifResult<ModuleResourceResponse> {
    let engine = Engine::default();
    // Safety: This function is inherently unsafe as the provided bytes:
    // 1. Are going to be deserialized directly into Rust objects.
    // 2. Contains the function assembly bodies and, if intercepted, a malicious actor could inject code into executable memory.
    // And as such, the deserialize method is unsafe.
    // However, there isn't much we can do about it here, we will warn users in elixir-land about this, though.
    let module = unsafe {
        Module::deserialize(&engine, binary.as_slice()).map_err(|e| {
            rustler::Error::Term(Box::new(format!("Could not deserialize module: {}", e)))
        })?
    };
    let resource = ResourceArc::new(ModuleResource {
        module: Mutex::new(module),
    });
    Ok(ModuleResourceResponse {
        ok: atoms::ok(),
        resource,
    })
}
