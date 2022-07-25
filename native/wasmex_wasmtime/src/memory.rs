//! Memory API of an WebAssembly instance.

use std::io::Write;
use std::sync::Mutex;

use rustler::resource::ResourceArc;
use rustler::{Atom, Binary, Error, NewBinary, NifResult, Term};

use wasmtime::{Instance, Memory, Store};

use crate::store::{WasmexStore, self};
use crate::{atoms, instance};

pub struct MemoryResource {
    pub inner: Mutex<Memory>,
}

#[derive(NifTuple)]
pub struct MemoryResourceResponse {
    ok: rustler::Atom,
    resource: ResourceArc<MemoryResource>,
}

#[rustler::nif(name = "memory_from_instance")]
pub fn from_instance(
    store_resource: ResourceArc<store::StoreResource>,
    instance_resource: ResourceArc<instance::InstanceResource>,
) -> rustler::NifResult<MemoryResourceResponse> {
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
                "Could not unlock store resource as the mutex was poisoned: {}",
                e
            )))
        })?);
    let memory = match store {
        WasmexStore::Plain(store) => memory_from_instance(&instance, store)?,
        WasmexStore::Wasi(store) => memory_from_instance(&instance, store)?,
    };
    let resource = ResourceArc::new(MemoryResource {
        inner: Mutex::new(memory.to_owned()),
    });

    Ok(MemoryResourceResponse {
        ok: atoms::ok(),
        resource,
    })
}

#[rustler::nif(name = "memory_length")]
pub fn length(resource: ResourceArc<MemoryResource>) -> NifResult<usize> {
    let memory = resource.inner.lock().unwrap();
    let store: Store<()> = Store::default(); // todo: get store
    let length = memory.data_size(store);
    Ok(length)
}

#[rustler::nif(name = "memory_grow")]
pub fn grow(resource: ResourceArc<MemoryResource>, pages: u64) -> NifResult<u64> {
    let memory = resource.inner.lock().unwrap();
    let mut store = Store::default(); // todo: get store
    let old_pages = grow_by_pages(&memory, &mut store, pages)?;
    Ok(old_pages)
}

/// Grows the memory by the given amount of pages. Returns the old page count.
fn grow_by_pages(
    memory: &Memory,
    store: &mut Store<()>,
    number_of_pages: u64,
) -> Result<u64, Error> {
    memory
        .grow(store, number_of_pages)
        .map(|previous_pages| previous_pages)
        .map_err(|err| Error::RaiseTerm(Box::new(format!("Failed to grow the memory: {}.", err))))
}

#[rustler::nif(name = "memory_get_byte")]
pub fn get_byte<'a>(resource: ResourceArc<MemoryResource>, offset: usize) -> NifResult<u8> {
    let memory = resource.inner.lock().unwrap();
    let mut store: Store<()> = Store::default(); // todo: get store

    let mut buffer = [0];
    memory
        .read(&mut store, offset, &mut buffer)
        .map_err(|err| Error::RaiseTerm(Box::new(err.to_string())))?;

    Ok(buffer[0])
}

#[rustler::nif(name = "memory_set_byte")]
pub fn set_byte<'a>(
    resource: ResourceArc<MemoryResource>,
    offset: usize,
    value: Term<'a>,
) -> NifResult<Atom> {
    let memory: Memory = *(resource.inner.lock().unwrap());
    let mut store: Store<()> = Store::default(); // todo: get store
    let value = value.decode()?;
    memory
        .write(&mut store, offset, &[value])
        .map_err(|err| Error::RaiseTerm(Box::new(err.to_string())))?;

    Ok(atoms::ok())
}

pub fn memory_from_instance<T>(instance: &Instance, store: &mut Store<T>) -> Result<Memory, Error> {
    instance
        .exports(store)
        .find_map(|export| export.into_memory())
        .ok_or_else(|| Error::RaiseTerm(Box::new("The WebAssembly module has no exported memory.")))
}

#[rustler::nif(name = "memory_read_binary")]
pub fn read_binary<'a>(
    env: rustler::Env<'a>,
    resource: ResourceArc<MemoryResource>,
    offset: usize,
    len: usize,
) -> NifResult<Binary<'a>> {
    let memory: Memory = *(resource.inner.lock().unwrap());
    let mut store: Store<()> = Store::default(); // todo: get store
    let mut buffer = vec![0u8; len];

    memory
        .read(&mut store, offset, &mut buffer)
        .map_err(|err| Error::RaiseTerm(Box::new(err.to_string())))?;
    let mut binary = NewBinary::new(env, len);
    binary.as_mut_slice().write_all(&buffer).unwrap();

    Ok(binary.into())
}

#[rustler::nif(name = "memory_write_binary")]
pub fn write_binary(
    resource: ResourceArc<MemoryResource>,
    offset: usize,
    binary: Binary,
) -> NifResult<Atom> {
    let memory: Memory = *(resource.inner.lock().unwrap());
    let mut store: Store<()> = Store::default(); // todo: get store
    memory
        .write(&mut store, offset, binary.as_slice())
        .map_err(|err| Error::RaiseTerm(Box::new(err.to_string())))?;
    Ok(atoms::ok())
}
