//! Kothon's dictation engine for phones: the same Bengali pipeline as the
//! desktop app (transcribe-cpp, then punctuation, numbers and English words),
//! behind a small C API that Swift (iOS) and Kotlin via JNI (Android) call.
//!
//! The pipeline order matches the desktop app's `managers/transcription.rs`:
//! model → punctuation → numbers/fillers → English words.

pub mod english;
pub mod ffi;
pub mod numbers;
#[cfg(feature = "punct")]
pub mod punct;

use std::path::{Path, PathBuf};
use std::sync::Mutex;

use anyhow::{anyhow, Result};
use once_cell::sync::OnceCell;
use transcribe_cpp::{Backend, ErrorKind, Model, ModelOptions, RunOptions, Session, Task, TimestampKind};

/// How the transcript is cleaned up after the model runs.
#[derive(Clone, Copy, Debug)]
pub struct Options {
    pub digits: Option<numbers::Digits>,
    pub remove_fillers: bool,
    pub english_words_in_english: bool,
    pub punctuation: bool,
    /// The BengaliAI Whisper fine-tune has no timestamp tokens.
    pub no_timestamps: bool,
    /// Run on the CPU. iOS refuses GPU (Metal) work from apps in the
    /// background, which is where the keyboard's dictations run.
    pub cpu_only: bool,
}

impl Default for Options {
    fn default() -> Self {
        Self {
            digits: Some(numbers::Digits::Bengali),
            remove_fillers: true,
            english_words_in_english: false,
            punctuation: true,
            no_timestamps: false,
            cpu_only: false,
        }
    }
}

static BACKENDS: OnceCell<()> = OnceCell::new();

fn init_backends() -> Result<()> {
    BACKENDS
        .get_or_try_init(|| {
            transcribe_cpp::init_logging();
            transcribe_cpp::init_backends_default().map_err(|e| anyhow!("{e}"))
        })
        .map(|_| ())
}

/// A loaded model and its session, on one backend.
struct Loaded {
    session: Session,
    // Keeps the model alive for as long as its session.
    _model: Model,
}

impl Loaded {
    fn load(path: &Path, backend: Backend) -> Result<Self> {
        let model = Model::load_with(
            path,
            &ModelOptions {
                backend,
                ..Default::default()
            },
        )
        .map_err(|e| anyhow!("Failed to load model: {e}"))?;
        let session = model
            .session()
            .map_err(|e| anyhow!("Failed to create session: {e}"))?;
        Ok(Self {
            session,
            _model: model,
        })
    }
}

/// The speech model, loaded on the GPU for foreground use and on the CPU for
/// background use, each only when first needed.
pub struct Engine {
    model_path: PathBuf,
    gpu: Mutex<Option<Loaded>>,
    cpu: Mutex<Option<Loaded>>,
    #[cfg(feature = "punct")]
    punctuator: Option<punct::Punctuator>,
}

impl Engine {
    /// Load a GGUF speech model, and the punctuation model if `punct_dir`
    /// holds one. A missing or broken punctuation model only turns
    /// punctuation off; it never stops dictation. `cpu_only` picks which
    /// copy of the speech model to load now (the other loads on demand).
    pub fn load(model_path: &Path, punct_dir: Option<&Path>, cpu_only: bool) -> Result<Self> {
        init_backends()?;
        let engine = Self {
            model_path: model_path.to_path_buf(),
            gpu: Mutex::new(None),
            cpu: Mutex::new(None),
            #[cfg(feature = "punct")]
            punctuator: punct_dir
                .filter(|d| d.join("model.safetensors").exists())
                .and_then(|d| match punct::Punctuator::load(d) {
                    Ok(p) => Some(p),
                    Err(e) => {
                        log::warn!("Kothon: punctuation model failed to load: {e:#}");
                        None
                    }
                }),
        };
        #[cfg(not(feature = "punct"))]
        let _ = punct_dir;
        engine.with_session(cpu_only, |_| Ok(()))?;
        Ok(engine)
    }

    fn with_session<T>(
        &self,
        cpu_only: bool,
        f: impl FnOnce(&mut Session) -> Result<T, transcribe_cpp::Error>,
    ) -> Result<T> {
        let (slot, backend) = if cpu_only {
            (&self.cpu, Backend::CpuAccel)
        } else {
            (&self.gpu, Backend::Auto)
        };
        let mut slot = slot.lock().map_err(|_| anyhow!("engine lock poisoned"))?;
        if slot.is_none() {
            *slot = Some(Loaded::load(&self.model_path, backend)?);
        }
        let loaded = slot.as_mut().expect("just loaded");
        f(&mut loaded.session).map_err(|e| {
            if e.kind() == ErrorKind::Backend {
                BackendError(e.to_string()).into()
            } else {
                anyhow!("{e}")
            }
        })
    }

    /// Free the GPU or CPU copy of the model, e.g. when the app goes to the
    /// background and only the CPU copy can run.
    pub fn unload(&self, cpu: bool) {
        let slot = if cpu { &self.cpu } else { &self.gpu };
        if let Ok(mut slot) = slot.lock() {
            *slot = None;
        }
    }

    /// 16 kHz mono f32 samples in, finished Bengali text out.
    pub fn transcribe(&self, pcm: &[f32], options: &Options) -> Result<String> {
        if pcm.is_empty() {
            return Ok(String::new());
        }
        let run = RunOptions {
            task: Task::Transcribe,
            language: Some("bn".to_string()),
            target_language: None,
            timestamps: if options.no_timestamps {
                TimestampKind::None
            } else {
                RunOptions::default().timestamps
            },
            ..Default::default()
        };
        let result = self.with_session(options.cpu_only, |s| s.run(pcm, &run));
        // The GPU can refuse work (on iOS, once the app is in the
        // background). The CPU always can, so try once more there.
        let transcript = match result {
            Err(e) if !options.cpu_only && e.is::<BackendError>() => {
                log::warn!("Kothon: GPU run failed ({e}), retrying on the CPU");
                self.with_session(true, |s| s.run(pcm, &run))?
            }
            other => other?,
        };
        Ok(self.post_process(transcript.text.trim(), options))
    }

    /// Everything after the model, so it can be tested without one.
    pub fn post_process(&self, text: &str, options: &Options) -> String {
        if text.is_empty() {
            return String::new();
        }
        #[allow(unused_mut)]
        let mut text = text.to_string();
        #[cfg(feature = "punct")]
        if options.punctuation {
            if let Some(p) = &self.punctuator {
                match p.punctuate(&text) {
                    Ok(out) => text = out,
                    Err(e) => log::warn!("Kothon: punctuation failed, keeping raw text: {e:#}"),
                }
            }
        }
        post_process_text(&text, options)
    }
}

/// Numbers, fillers and English words: rule-based, no model needed.
pub fn post_process_text(text: &str, options: &Options) -> String {
    let text = match options.digits {
        Some(style) => numbers::clean(text, style, options.remove_fillers),
        None => text.to_string(),
    };
    if options.english_words_in_english {
        english::english_words_in_english(&text)
    } else {
        text
    }
}

/// A failure in the compute backend (as opposed to bad input).
#[derive(Debug)]
struct BackendError(String);

impl std::fmt::Display for BackendError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "backend error: {}", self.0)
    }
}

impl std::error::Error for BackendError {}
