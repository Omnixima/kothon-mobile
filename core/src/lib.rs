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

use std::path::Path;
use std::sync::Mutex;

use anyhow::{anyhow, Result};
use once_cell::sync::OnceCell;
use transcribe_cpp::{Model, ModelOptions, RunOptions, Session, Task, TimestampKind};

/// How the transcript is cleaned up after the model runs.
#[derive(Clone, Copy, Debug)]
pub struct Options {
    pub digits: Option<numbers::Digits>,
    pub remove_fillers: bool,
    pub english_words_in_english: bool,
    pub punctuation: bool,
    /// The BengaliAI Whisper fine-tune has no timestamp tokens.
    pub no_timestamps: bool,
}

impl Default for Options {
    fn default() -> Self {
        Self {
            digits: Some(numbers::Digits::Bengali),
            remove_fillers: true,
            english_words_in_english: false,
            punctuation: true,
            no_timestamps: false,
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

pub struct Engine {
    session: Mutex<Session>,
    #[cfg(feature = "punct")]
    punctuator: Option<punct::Punctuator>,
    // Keeps the model alive for as long as its session.
    _model: Model,
}

impl Engine {
    /// Load a GGUF speech model, and the punctuation model if `punct_dir`
    /// holds one. A missing or broken punctuation model only turns
    /// punctuation off; it never stops dictation.
    pub fn load(model_path: &Path, punct_dir: Option<&Path>) -> Result<Self> {
        init_backends()?;
        let model = Model::load_with(model_path, &ModelOptions::default())
            .map_err(|e| anyhow!("Failed to load model: {e}"))?;
        let session = model
            .session()
            .map_err(|e| anyhow!("Failed to create session: {e}"))?;
        #[cfg(feature = "punct")]
        let punctuator = punct_dir
            .filter(|d| d.join("model.safetensors").exists())
            .and_then(|d| match punct::Punctuator::load(d) {
                Ok(p) => Some(p),
                Err(e) => {
                    log::warn!("Kothon: punctuation model failed to load: {e:#}");
                    None
                }
            });
        #[cfg(not(feature = "punct"))]
        let _ = punct_dir;
        Ok(Self {
            session: Mutex::new(session),
            #[cfg(feature = "punct")]
            punctuator,
            _model: model,
        })
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
        let text = {
            let mut session = self
                .session
                .lock()
                .map_err(|_| anyhow!("engine lock poisoned"))?;
            session.run(pcm, &run).map_err(|e| anyhow!("{e}"))?.text
        };
        Ok(self.post_process(text.trim(), options))
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
