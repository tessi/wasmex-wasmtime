use wasmtime::Func;
use wasmtime::Instance;
use wasmtime::Store;

pub fn exists<T>(instance: &Instance, store: &mut Store<T>, name: &str) -> bool {
    find(instance, store, name).is_some()
}

pub fn find<T>(instance: &Instance, store: &mut Store<T>, name: &str) -> Option<Func> {
    instance.get_func(store, name)
}
