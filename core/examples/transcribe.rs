//! Transcribe WAV files with kothon-core, for accuracy and speed checks on a
//! Mac (Metal) against other engines.
//!
//!   cargo run --release --example transcribe -- MODEL.gguf [--whisper] a.wav b.wav ...
//!
//! Prints one line per file: path, milliseconds, text (tab-separated). Raw
//! model text: no punctuation model, numbers left as words.

use std::path::Path;
use std::time::Instant;

use kothon_core::{Engine, Options};

fn read_wav_16k(path: &str) -> anyhow::Result<Vec<f32>> {
    let mut reader = hound::WavReader::open(path)?;
    let spec = reader.spec();
    anyhow::ensure!(spec.sample_rate == 16_000, "{path}: need 16 kHz, got {}", spec.sample_rate);
    let ch = spec.channels as usize;
    let samples: Vec<f32> = match spec.sample_format {
        hound::SampleFormat::Float => reader.samples::<f32>().collect::<Result<_, _>>()?,
        hound::SampleFormat::Int => {
            let scale = (1i64 << (spec.bits_per_sample - 1)) as f32;
            reader
                .samples::<i32>()
                .map(|s| s.map(|v| v as f32 / scale))
                .collect::<Result<_, _>>()?
        }
    };
    Ok(samples.chunks(ch).map(|c| c.iter().sum::<f32>() / ch as f32).collect())
}

fn main() -> anyhow::Result<()> {
    let mut args: Vec<String> = std::env::args().skip(1).collect();
    anyhow::ensure!(!args.is_empty(), "usage: transcribe MODEL.gguf [--whisper] files...");
    let model = args.remove(0);
    let whisper = args.first().map(|a| a == "--whisper").unwrap_or(false);
    if whisper {
        args.remove(0);
    }
    let engine = Engine::load(Path::new(&model), None, false)?;
    let options = Options {
        digits: None,
        remove_fillers: false,
        english_words_in_english: false,
        punctuation: false,
        no_timestamps: whisper,
        cpu_only: false,
    };
    for path in args {
        let pcm = read_wav_16k(&path)?;
        let t = Instant::now();
        let text = engine.transcribe(&pcm, &options)?;
        println!("{path}\t{}\t{}", t.elapsed().as_millis(), text.replace(['\t', '\n'], " "));
    }
    Ok(())
}
