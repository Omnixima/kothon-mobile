//! Speech detection before transcription. Whisper invents words when given
//! silence ("stop" pressed without speaking), so a recording with no speech
//! produces no text, and silence around speech is trimmed off. Uses the same
//! Silero VAD v6.2 model and threshold as the desktop app.

use std::path::Path;
use std::sync::Mutex;

use anyhow::{anyhow, Result};
use transcribe_cpp::{Backend, Model, ModelOptions, VadOptions, VadSession, VadSessionOptions};

/// The desktop app's Silero threshold (managers/audio.rs).
const THRESHOLD: f64 = 0.3;

pub struct Vad {
    session: Mutex<VadSession>,
}

impl Vad {
    pub fn load(path: &Path) -> Result<Self> {
        crate::init_backends()?;
        let model = Model::load_with(
            path,
            &ModelOptions {
                backend: Backend::Cpu,
                ..Default::default()
            },
        )
        .map_err(|e| anyhow!("Failed to load VAD model: {e}"))?;
        let session = model
            .vad_session_with(&VadSessionOptions { n_threads: 1 })
            .map_err(|e| anyhow!("Failed to create VAD session: {e}"))?;
        Ok(Self {
            session: Mutex::new(session),
        })
    }

    /// The part of `pcm` from the first to the last speech, padded by 0.3 s,
    /// or `None` when there is no speech at all.
    pub fn speech_range(&self, pcm: &[f32]) -> Result<Option<(usize, usize)>> {
        let mut session = self.session.lock().map_err(|_| anyhow!("VAD lock poisoned"))?;
        let result = session
            .run(
                pcm,
                &VadOptions {
                    threshold: THRESHOLD,
                    min_speech_ms: 200,
                    speech_pad_ms: 300,
                    ..Default::default()
                },
            )
            .map_err(|e| anyhow!("VAD failed: {e}"))?;
        let (Some(first), Some(last)) = (result.segments.first(), result.segments.last()) else {
            return Ok(None);
        };
        let start = first.start_sample.clamp(0, pcm.len() as i64) as usize;
        let end = last.end_sample.clamp(0, pcm.len() as i64) as usize;
        Ok((end > start).then_some((start, end)))
    }
}

/// Without the VAD model: treat a recording as silent when no 100 ms window
/// is louder than a whisper. Rough, but it catches an empty recording.
pub fn has_energy(pcm: &[f32]) -> bool {
    pcm.chunks(1600).any(|w| {
        let rms = (w.iter().map(|x| x * x).sum::<f32>() / w.len() as f32).sqrt();
        rms > 0.01
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn silence_has_no_energy() {
        assert!(!has_energy(&vec![0.001f32; 16_000]));
        let mut pcm = vec![0.0f32; 16_000];
        pcm[8_000..9_600].iter_mut().for_each(|x| *x = 0.2);
        assert!(has_energy(&pcm));
    }
}
