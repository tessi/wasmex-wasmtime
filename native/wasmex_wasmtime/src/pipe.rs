//! A Pipe is a file buffer hold in memory.
//! It can, for example, be used to replace stdin/stdout/stderr of a WASI module.

use std::any::Any;
use std::io::Write;
use std::io::{self, Read, Seek};
use std::sync::{Arc, Mutex, RwLock};

use rustler::resource::ResourceArc;
use rustler::{Atom, Encoder, Term};

use wasi_common::file::{FdFlags, FileType};
use wasi_common::Error;
use wasi_common::WasiFile;

use crate::atoms;

/// For piping stdio. Stores all output / input in a byte-vector.
#[derive(Debug, Default)]
pub struct Pipe {
    buffer: Arc<RwLock<Vec<u8>>>,
}

impl Pipe {
    pub fn new() -> Self {
        Self::default()
    }
    fn borrow(&self) -> std::sync::RwLockWriteGuard<Vec<u8>> {
        RwLock::write(&self.buffer).unwrap()
    }

    fn size(&self) -> u64 {
        (*self.borrow()).len() as u64
    }

    fn set_len(&mut self, len: u64) {
        let mut buffer = self.borrow();
        buffer.resize(len as usize, 0);
    }
}

impl Clone for Pipe {
    fn clone(&self) -> Self {
        Self {
            buffer: self.buffer.clone(),
        }
    }
}

impl Read for Pipe {
    fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
        let mut buffer = self.borrow();
        let amt = std::cmp::min(buf.len(), buffer.len());
        for (i, byte) in buffer.drain(..amt).enumerate() {
            buf[i] = byte;
        }
        Ok(amt)
    }
}

impl Write for Pipe {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        let mut buffer = self.borrow();
        buffer.extend(buf);
        Ok(buf.len())
    }
    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

impl Seek for Pipe {
    fn seek(&mut self, _pos: io::SeekFrom) -> io::Result<u64> {
        Err(io::Error::new(
            io::ErrorKind::Other,
            "can not seek in a pipe",
        ))
    }
}

#[wiggle::async_trait]
impl WasiFile for Pipe {
    fn as_any(&self) -> &dyn Any {
        self
    }

    async fn get_filetype(&mut self) -> Result<FileType, Error> {
        Ok(FileType::Pipe)
    }
    async fn get_fdflags(&mut self) -> Result<FdFlags, Error> {
        Ok(FdFlags::APPEND)
    }
}

pub struct PipeResource {
    pub pipe: Mutex<Pipe>,
}

#[derive(NifTuple)]
pub struct PipeResourceResponse {
    ok: rustler::Atom,
    resource: ResourceArc<PipeResource>,
}

#[rustler::nif(name = "pipe_create")]
pub fn create() -> PipeResourceResponse {
    let pipe = Pipe::new();
    let pipe_resource = ResourceArc::new(PipeResource {
        pipe: Mutex::new(pipe),
    });

    PipeResourceResponse {
        ok: atoms::ok(),
        resource: pipe_resource,
    }
}

#[rustler::nif(name = "pipe_size")]
pub fn size(pipe_resource: ResourceArc<PipeResource>) -> u64 {
    pipe_resource.pipe.lock().unwrap().size()
}

#[rustler::nif(name = "pipe_set_len")]
pub fn set_len(pipe_resource: ResourceArc<PipeResource>, len: u64) -> Atom {
    let mut pipe = pipe_resource.pipe.lock().unwrap();

    pipe.set_len(len);
    atoms::ok()
}

#[rustler::nif(name = "pipe_read_binary")]
pub fn read_binary(pipe_resource: ResourceArc<PipeResource>) -> String {
    let mut pipe = pipe_resource.pipe.lock().unwrap();
    let mut buffer = String::new();

    (*pipe).read_to_string(&mut buffer).unwrap();
    buffer
}

#[rustler::nif(name = "pipe_write_binary")]
pub fn write_binary(
    env: rustler::Env,
    pipe_resource: ResourceArc<PipeResource>,
    content: String,
) -> Term {
    let mut pipe = pipe_resource.pipe.lock().unwrap();

    match (*pipe).write(content.as_bytes()) {
        Ok(bytes_written) => (atoms::ok(), bytes_written).encode(env),
        _ => atoms::error().encode(env),
    }
}
