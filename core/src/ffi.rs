//! The C API (see `include/kothon_core.h`). Every string returned here is
//! owned by the caller and must be released with `kothon_string_free`.

use std::ffi::{c_char, CStr, CString};
use std::path::Path;
use std::ptr;

use crate::{numbers::Digits, Engine, Options};

/// Mirrors `KothonOptions` in the header.
#[repr(C)]
pub struct KothonOptions {
    /// 0 = Bengali digits (২০২৬), 1 = Latin digits (2026), 2 = leave numbers as words.
    pub digits: u8,
    pub remove_fillers: bool,
    pub english_words_in_english: bool,
    pub punctuation: bool,
    pub no_timestamps: bool,
    /// Run on the CPU (iOS apps in the background can't use the GPU).
    pub cpu_only: bool,
}

impl From<&KothonOptions> for Options {
    fn from(o: &KothonOptions) -> Self {
        Options {
            digits: match o.digits {
                0 => Some(Digits::Bengali),
                1 => Some(Digits::Latin),
                _ => None,
            },
            remove_fillers: o.remove_fillers,
            english_words_in_english: o.english_words_in_english,
            punctuation: o.punctuation,
            no_timestamps: o.no_timestamps,
            cpu_only: o.cpu_only,
        }
    }
}

fn to_c(s: impl Into<Vec<u8>>) -> *mut c_char {
    CString::new(s)
        .map(CString::into_raw)
        .unwrap_or(ptr::null_mut())
}

fn set_err(err_out: *mut *mut c_char, msg: String) {
    if !err_out.is_null() {
        unsafe { *err_out = to_c(msg.replace('\0', " ")) };
    }
}

unsafe fn path_arg<'a>(p: *const c_char) -> Option<&'a Path> {
    if p.is_null() {
        return None;
    }
    CStr::from_ptr(p).to_str().ok().map(Path::new)
}

/// Load a model. Returns NULL and sets `*err_out` on failure.
#[no_mangle]
pub unsafe extern "C" fn kothon_engine_new(
    model_path: *const c_char,
    punct_dir: *const c_char,
    cpu_only: bool,
    err_out: *mut *mut c_char,
) -> *mut Engine {
    let Some(model) = path_arg(model_path) else {
        set_err(err_out, "model path is missing or not UTF-8".into());
        return ptr::null_mut();
    };
    match std::panic::catch_unwind(|| Engine::load(model, path_arg(punct_dir), cpu_only)) {
        Ok(Ok(engine)) => Box::into_raw(Box::new(engine)),
        Ok(Err(e)) => {
            set_err(err_out, format!("{e:#}"));
            ptr::null_mut()
        }
        Err(_) => {
            set_err(err_out, "the engine panicked while loading".into());
            ptr::null_mut()
        }
    }
}

/// Transcribe 16 kHz mono f32 samples. Returns NULL and sets `*err_out` on failure.
#[no_mangle]
pub unsafe extern "C" fn kothon_transcribe(
    engine: *const Engine,
    pcm: *const f32,
    n_samples: usize,
    options: *const KothonOptions,
    err_out: *mut *mut c_char,
) -> *mut c_char {
    if engine.is_null() || (pcm.is_null() && n_samples > 0) {
        set_err(err_out, "null engine or audio".into());
        return ptr::null_mut();
    }
    let engine = &*engine;
    let samples: &[f32] = if n_samples == 0 {
        &[]
    } else {
        std::slice::from_raw_parts(pcm, n_samples)
    };
    let opts = if options.is_null() {
        Options::default()
    } else {
        Options::from(&*options)
    };
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        engine.transcribe(samples, &opts)
    })) {
        Ok(Ok(text)) => to_c(text),
        Ok(Err(e)) => {
            set_err(err_out, format!("{e:#}"));
            ptr::null_mut()
        }
        Err(_) => {
            set_err(err_out, "the engine panicked while transcribing".into());
            ptr::null_mut()
        }
    }
}

/// Numbers, fillers and English words only (no models). Handy for tests.
#[no_mangle]
pub unsafe extern "C" fn kothon_post_process(
    text: *const c_char,
    options: *const KothonOptions,
) -> *mut c_char {
    if text.is_null() {
        return ptr::null_mut();
    }
    let text = CStr::from_ptr(text).to_string_lossy();
    let opts = if options.is_null() {
        Options::default()
    } else {
        Options::from(&*options)
    };
    to_c(crate::post_process_text(&text, &opts))
}

/// Free the GPU (`cpu` = false) or CPU copy of the model. It reloads on demand.
#[no_mangle]
pub unsafe extern "C" fn kothon_engine_unload(engine: *const Engine, cpu: bool) {
    if !engine.is_null() {
        (*engine).unload(cpu);
    }
}

/// Set CPU threads (0 = default) and whether to use Accelerate; the CPU copy reloads.
#[no_mangle]
pub unsafe extern "C" fn kothon_engine_set_cpu(engine: *const Engine, n_threads: i32, accel: bool) {
    if !engine.is_null() {
        (*engine).set_cpu_config(n_threads, accel);
    }
}

#[no_mangle]
pub unsafe extern "C" fn kothon_engine_free(engine: *mut Engine) {
    if !engine.is_null() {
        drop(Box::from_raw(engine));
    }
}

#[no_mangle]
pub unsafe extern "C" fn kothon_string_free(s: *mut c_char) {
    if !s.is_null() {
        drop(CString::from_raw(s));
    }
}
