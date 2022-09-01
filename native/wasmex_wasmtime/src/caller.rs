use once_cell::sync::Lazy;
use std::{collections::HashMap, sync::Mutex};
use wasmtime::Caller;

use crate::store::StoreData;

static GLOBAL_DATA: Lazy<Mutex<HashMap<i32, Caller<StoreData>>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));

pub(crate) fn get_caller<'a>(token: &'a i32) -> Option<&'a Caller<'a, StoreData>> {
    let map = &*(GLOBAL_DATA.lock().unwrap());
    map.get(&token).map(|caller| {
        let caller = unsafe {
            std::mem::transmute::<&Caller<'_, StoreData>, &Caller<'a, StoreData>>(caller)
        };
        caller
    })
}

pub(crate) fn get_caller_mut<'a>(token: &'a i32) -> Option<&'a mut Caller<'a, StoreData>> {
    let map = &mut *(GLOBAL_DATA.lock().unwrap());
    map.get_mut(&token)
        // .map(|&caller_addr| mut_borrow_from_caller_addr(caller_addr))
        .map(|caller| {
            let caller = unsafe {
                std::mem::transmute::<&mut Caller<'_, StoreData>, &mut Caller<'a, StoreData>>(
                    caller,
                )
            };
            caller
        })
}

pub(crate) fn set_caller(caller: Caller<StoreData>) -> i32 {
    let mut map = GLOBAL_DATA.lock().unwrap();
    // let caller = horrible_hack(caller);
    // TODO: prevent duplicates by throwing the dice again when the id is already known
    let token = rand::random();
    let caller =
        unsafe { std::mem::transmute::<Caller<'_, StoreData>, Caller<'static, StoreData>>(caller) };
    map.insert(token, caller);
    token
}

pub(crate) fn remove_caller(token: i32) {
    let mut map = GLOBAL_DATA.lock().unwrap();
    map.remove(&token);
}
