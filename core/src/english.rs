//! Kothon: write English words spoken inside Bengali in English.
//!
//! Bengali speakers mix in English words ("আমি মিটিংয়ে আছি"). The Bengali
//! models spell them in Bengali script. With this option on, known English
//! words go back to English, keeping Bengali case endings after a hyphen
//! ("আমি meeting-এ আছি"), the usual way Banglish is written. A lookup per
//! word against a built-in list (kothon_english.tsv); no model involved.

use std::collections::HashMap;

use once_cell::sync::Lazy;

static LEXICON: Lazy<HashMap<&'static str, &'static str>> = Lazy::new(|| {
    include_str!("kothon_english.tsv")
        .lines()
        .filter(|l| !l.starts_with('#') && !l.trim().is_empty())
        .filter_map(|l| l.split_once('\t'))
        .map(|(bn, en)| (bn.trim(), en.trim()))
        .collect()
});

/// Bengali endings that can follow an English word, as written after it.
/// Longest first, so "য়ের" wins over "ের".
const SUFFIXES: &[(&str, &str)] = &[
    ("গুলোতে", "গুলোতে"),
    ("গুলোর", "গুলোর"),
    ("গুলো", "গুলো"),
    ("গুলি", "গুলি"),
    ("দেরকে", "দেরকে"),
    ("দের", "দের"),
    ("টাকে", "টাকে"),
    ("টার", "টার"),
    ("টাও", "টাও"),
    ("টা", "টা"),
    ("টির", "টির"),
    ("টি", "টি"),
    ("য়ের", "এর"),
    ("য়ে", "এ"),
    ("তে", "তে"),
    ("কে", "কে"),
    ("রা", "রা"),
    ("ের", "এর"),
    ("এর", "এর"),
    ("র", "এর"),
    ("ে", "এ"),
    ("এ", "এ"),
    ("ও", "ও"),
    ("ই", "ই"),
];

fn is_punct(c: char) -> bool {
    c.is_ascii_punctuation() || matches!(c, '।' | '॥' | '“' | '”' | '‘' | '’' | '…')
}

/// The English form of one Bengali-script word, ending included, if known.
fn convert_word(word: &str) -> Option<String> {
    if let Some(en) = LEXICON.get(word) {
        return Some((*en).to_string());
    }
    for (bn_suffix, out_suffix) in SUFFIXES {
        if let Some(stem) = word.strip_suffix(bn_suffix) {
            if let Some(en) = LEXICON.get(stem) {
                return Some(format!("{en}-{out_suffix}"));
            }
        }
    }
    None
}

/// Rewrite known English words in `text`, leaving everything else as is.
pub fn english_words_in_english(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for (i, token) in text.split(' ').enumerate() {
        if i > 0 {
            out.push(' ');
        }
        let start = token.len() - token.trim_start_matches(is_punct).len();
        let end = token.trim_end_matches(is_punct).len();
        if start >= end {
            out.push_str(token);
            continue;
        }
        match convert_word(&token[start..end]) {
            Some(en) => {
                out.push_str(&token[..start]);
                out.push_str(&en);
                out.push_str(&token[end..]);
            }
            None => out.push_str(token),
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn converts_words_and_keeps_endings() {
        assert_eq!(
            english_words_in_english("আমি মিটিংয়ে আছি, পরে ফোন করব।"),
            "আমি meeting-এ আছি, পরে phone করব।"
        );
        assert_eq!(english_words_in_english("অফিসের ফাইলটা"), "office-এর file-টা");
        assert_eq!(english_words_in_english("ইমেইলগুলো দেখো"), "email-গুলো দেখো");
    }

    #[test]
    fn leaves_bengali_words_alone() {
        let s = "আজ আবহাওয়া খুব সুন্দর। তুমি কি বসবে?";
        assert_eq!(english_words_in_english(s), s);
        // "বস" (sit) and "বাস" (dwell) are not in the list on purpose.
        assert_eq!(english_words_in_english("বস বাস"), "বস বাস");
    }

    #[test]
    fn lexicon_loads() {
        assert!(LEXICON.len() > 200);
        assert_eq!(LEXICON.get("মিটিং"), Some(&"meeting"));
    }
}
