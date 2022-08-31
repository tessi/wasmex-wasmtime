use once_cell::sync::Lazy;
use std::{collections::HashMap, sync::Mutex};
use wasmtime::Caller;

use crate::store::StoreData;

static GLOBAL_DATA: Lazy<Mutex<HashMap<i32, usize>>> = Lazy::new(|| Mutex::new(HashMap::new()));

pub(crate) fn get_caller<'a>(token: i32) -> Option<&'a mut Caller<'a, StoreData>> {
    let map = &*(GLOBAL_DATA.lock().unwrap());
    map.get(&token)
        .map(|&caller_addr| mut_borrow_from_caller_addr(caller_addr))
}

pub(crate) fn set_caller(caller: &Caller<StoreData>) -> i32 {
    let mut map = GLOBAL_DATA.lock().unwrap();
    // let caller = horrible_hack(caller);
    // TODO: prevent duplicates by throwing the dice again when the id is already known
    let token = rand::random();
    map.insert(token, addr_of_caller(caller));
    token
}

pub(crate) fn remove_caller(token: i32) {
    let mut map = GLOBAL_DATA.lock().unwrap();
    map.remove(&token);
}

// TODO: properly document what the hell this is and why
// the ugliest hack invented in history:
// we convert the caller into a raw pointer, and then into a usize representing the memory address of it
// only to strip it of nasty lifetimes so we can pass it up to elixir land.
// it's as unsafe as it gets and we must never de-reference it outside of the function context
// this is "ensured" by giving out an id to this HashMap instead of to the caller address itself.
fn addr_of_caller(caller: &Caller<StoreData>) -> usize {
    (std::ptr::addr_of!(caller)) as usize
}

fn mut_borrow_from_caller_addr<'a>(ptr: usize) -> &'a mut Caller<'a, StoreData> {
    let ptr = ptr as *mut Caller<StoreData>;
    unsafe { &mut *ptr as &mut Caller<StoreData> }
}

// fn horrible_hack<'a, 'b>(caller: &'a Caller<StoreData>) -> Caller<'b, StoreData> {
//     let raw = (std::ptr::addr_of!(caller)) as usize;
//     let ptr = raw as *mut Caller<StoreData>;
//     unsafe { std::ptr::read(ptr) }
// }

// fn horrible_hack_mut_borrow<'a, 'b>(caller: &'a Caller<StoreData>) -> &'b mut Caller<'b, StoreData> {
//     let raw = (std::ptr::addr_of!(caller)) as usize;
//     let ptr = raw as *mut Caller<StoreData>;
//     unsafe { &mut *ptr as &mut Caller<StoreData> }
// }
