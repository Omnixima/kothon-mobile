//! Kothon: on-device Bengali punctuation restoration.
//!
//! Neither Bengali speech model outputs punctuation. This adds দাঁড়ি (।),
//! commas and question marks with a small token classifier: the 6-layer MuRIL
//! punctuation model from the BengaliAI competition winner (Apache-2.0),
//! with its vocab pruned to Bengali script and stored as F16 (~128 MB).
//! It runs on the CPU in candle (Accelerate on Apple platforms).
//!
//! Copied from the desktop app (src-tauri/src/kothon_punct.rs); downloading
//! is left to the phone app, which owns the network and storage.
//!
//! Files (in `<models dir>/bn-punct-muril6/`): `config.json`,
//! `model.safetensors`, `tokenizer.json`.

use std::path::Path;

use anyhow::{anyhow, Result};
use candle_core::{DType, Device, Tensor, D};
use candle_nn::{Linear, Module, VarBuilder};
use candle_transformers::models::bert::{BertModel, Config};
use tokenizers::Tokenizer;

pub const PUNCT_DIR: &str = "bn-punct-muril6";

/// Words per model call. Well under the 512-token limit for Bengali text.
const WINDOW_WORDS: usize = 150;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Mark {
    None,
    Danda,
    Comma,
    Question,
}

pub struct Punctuator {
    bert: BertModel,
    classifier: Linear,
    tokenizer: Tokenizer,
    labels: Vec<Mark>,
    device: Device,
}

impl Punctuator {
    pub fn load(dir: &Path) -> Result<Self> {
        let device = Device::Cpu;
        let config_text = std::fs::read_to_string(dir.join("config.json"))?;
        let config: Config = serde_json::from_str(&config_text)?;
        let raw: serde_json::Value = serde_json::from_str(&config_text)?;
        let id2label = raw["id2label"]
            .as_object()
            .ok_or_else(|| anyhow!("config.json has no id2label"))?;
        let mut labels = vec![Mark::None; id2label.len()];
        for (id, name) in id2label {
            let i: usize = id.parse()?;
            labels[i] = match name.as_str().unwrap_or("") {
                "PERIOD" => Mark::Danda,
                "COMMA" => Mark::Comma,
                "QUESTION" => Mark::Question,
                _ => Mark::None,
            };
        }
        // F16 on disk, F32 compute: candle's CPU F16 matmul is slow.
        let vb = unsafe {
            VarBuilder::from_mmaped_safetensors(
                &[dir.join("model.safetensors")],
                DType::F32,
                &device,
            )?
        };
        let bert = BertModel::load(vb.pp("bert"), &config)?;
        let classifier = candle_nn::linear(config.hidden_size, labels.len(), vb.pp("classifier"))?;
        let tokenizer = Tokenizer::from_file(dir.join("tokenizer.json")).map_err(|e| anyhow!(e))?;
        Ok(Self {
            bert,
            classifier,
            tokenizer,
            labels,
            device,
        })
    }

    /// One mark per word, read from each word's first sub-token.
    fn predict(&self, words: &[&str]) -> Result<Vec<Mark>> {
        let enc = self
            .tokenizer
            .encode(tokenizers::InputSequence::from(words.to_vec()), true)
            .map_err(|e| anyhow!(e))?;
        let ids = enc.get_ids();
        let input = Tensor::new(ids, &self.device)?.unsqueeze(0)?;
        let types = input.zeros_like()?;
        let hidden = self.bert.forward(&input, &types, None)?;
        let pred: Vec<u32> = self
            .classifier
            .forward(&hidden)?
            .argmax(D::Minus1)?
            .squeeze(0)?
            .to_vec1()?;
        let mut marks = vec![Mark::None; words.len()];
        let mut prev = None;
        for (i, wid) in enc.get_word_ids().iter().enumerate() {
            if let Some(w) = wid {
                if prev != Some(*w) {
                    marks[*w as usize] = self.labels[pred[i] as usize];
                }
            }
            prev = *wid;
        }
        Ok(marks)
    }

    /// Punctuate unpunctuated Bengali text. Text that already has
    /// punctuation is returned as is.
    pub fn punctuate(&self, text: &str) -> Result<String> {
        if text
            .chars()
            .any(|c| matches!(c, '।' | '?' | ',' | '!' | '.'))
        {
            return Ok(text.to_string());
        }
        let words: Vec<&str> = text.split_whitespace().collect();
        if words.is_empty() {
            return Ok(text.to_string());
        }
        let mut marks = Vec::with_capacity(words.len());
        for chunk in words.chunks(WINDOW_WORDS) {
            marks.extend(self.predict(chunk)?);
        }
        // A dictated utterance always ends a sentence.
        if let Some(last) = marks.last_mut() {
            if *last != Mark::Question {
                *last = Mark::Danda;
            }
        }
        let mut out = String::with_capacity(text.len() + words.len());
        for (i, (w, m)) in words.iter().zip(marks).enumerate() {
            if i > 0 {
                out.push(' ');
            }
            out.push_str(w);
            match m {
                Mark::Danda => out.push('।'),
                Mark::Comma => out.push(','),
                Mark::Question => out.push('?'),
                Mark::None => {}
            }
        }
        Ok(out)
    }
}
