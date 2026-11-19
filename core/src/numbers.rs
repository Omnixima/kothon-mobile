//! Kothon: clean up Bengali dictation. Spoken numbers become digits
//! ("দুই হাজার সতেরো" → "২০১৭", "আট লাখ" → "৮,০০,০০০"), with percent
//! ("পঞ্চাশ শতাংশ" → "৫০%") and decimals ("তিন দশমিক পাঁচ" → "৩.৫"), and
//! hesitation sounds (উম, হুম...) are dropped. Rule-based, a few µs.
//!
//! Small numbers (under ten) stay as words unless they're part of a bigger
//! one, since Bengali prose spells them out and some are also ordinary
//! words: "নয়" is nine but also "is not", "এক" is also "a".

use std::collections::HashMap;

use once_cell::sync::Lazy;

/// How digits are written.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Digits {
    /// ০১২৩৪৫৬৭৮৯
    Bengali,
    /// 0123456789
    Latin,
}

/// 1–99 in words (with common spelling variants).
static NUMBERS: Lazy<HashMap<&'static str, u64>> = Lazy::new(|| {
    let table: &[(&str, u64)] = &[
        ("এক", 1),
        ("দুই", 2),
        ("দুই", 2),
        ("দু", 2),
        ("তিন", 3),
        ("চার", 4),
        ("পাঁচ", 5),
        ("ছয়", 6),
        ("ছয়", 6),
        ("ছয়", 6),
        ("সাত", 7),
        ("আট", 8),
        ("নয়", 9),
        ("নয়", 9),
        ("দশ", 10),
        ("এগারো", 11),
        ("এগারো", 11),
        ("এগার", 11),
        ("বারো", 12),
        ("বার", 12),
        ("তেরো", 13),
        ("তের", 13),
        ("চৌদ্দ", 14),
        ("চোদ্দ", 14),
        ("পনেরো", 15),
        ("পনের", 15),
        ("ষোলো", 16),
        ("ষোল", 16),
        ("সতেরো", 17),
        ("সতের", 17),
        ("আঠারো", 18),
        ("আঠার", 18),
        ("উনিশ", 19),
        ("বিশ", 20),
        ("কুড়ি", 20),
        ("কুড়ি", 20),
        ("একুশ", 21),
        ("বাইশ", 22),
        ("তেইশ", 23),
        ("চব্বিশ", 24),
        ("পঁচিশ", 25),
        ("ছাব্বিশ", 26),
        ("সাতাশ", 27),
        ("আটাশ", 28),
        ("ঊনত্রিশ", 29),
        ("উনত্রিশ", 29),
        ("ত্রিশ", 30),
        ("তিরিশ", 30),
        ("একত্রিশ", 31),
        ("বত্রিশ", 32),
        ("তেত্রিশ", 33),
        ("চৌত্রিশ", 34),
        ("পঁয়ত্রিশ", 35),
        ("পঁয়ত্রিশ", 35),
        ("ছত্রিশ", 36),
        ("সাঁইত্রিশ", 37),
        ("আটত্রিশ", 38),
        ("ঊনচল্লিশ", 39),
        ("উনচল্লিশ", 39),
        ("চল্লিশ", 40),
        ("একচল্লিশ", 41),
        ("বিয়াল্লিশ", 42),
        ("বিয়াল্লিশ", 42),
        ("তেতাল্লিশ", 43),
        ("চুয়াল্লিশ", 44),
        ("চুয়াল্লিশ", 44),
        ("পঁয়তাল্লিশ", 45),
        ("পঁয়তাল্লিশ", 45),
        ("ছেচল্লিশ", 46),
        ("সাতচল্লিশ", 47),
        ("আটচল্লিশ", 48),
        ("ঊনপঞ্চাশ", 49),
        ("উনপঞ্চাশ", 49),
        ("পঞ্চাশ", 50),
        ("একান্ন", 51),
        ("বাহান্ন", 52),
        ("বায়ান্ন", 52),
        ("বায়ান্ন", 52),
        ("তিপ্পান্ন", 53),
        ("চুয়ান্ন", 54),
        ("চুয়ান্ন", 54),
        ("পঞ্চান্ন", 55),
        ("ছাপ্পান্ন", 56),
        ("সাতান্ন", 57),
        ("আটান্ন", 58),
        ("ঊনষাট", 59),
        ("উনষাট", 59),
        ("ষাট", 60),
        ("একষট্টি", 61),
        ("বাষট্টি", 62),
        ("তেষট্টি", 63),
        ("চৌষট্টি", 64),
        ("পঁয়ষট্টি", 65),
        ("পঁয়ষট্টি", 65),
        ("ছেষট্টি", 66),
        ("সাতষট্টি", 67),
        ("আটষট্টি", 68),
        ("ঊনসত্তর", 69),
        ("উনসত্তর", 69),
        ("সত্তর", 70),
        ("একাত্তর", 71),
        ("বাহাত্তর", 72),
        ("বায়াত্তর", 72),
        ("তিয়াত্তর", 73),
        ("তিয়াত্তর", 73),
        ("চুয়াত্তর", 74),
        ("চুয়াত্তর", 74),
        ("পঁচাত্তর", 75),
        ("ছিয়াত্তর", 76),
        ("ছিয়াত্তর", 76),
        ("সাতাত্তর", 77),
        ("আটাত্তর", 78),
        ("ঊনআশি", 79),
        ("উনআশি", 79),
        ("আশি", 80),
        ("একাশি", 81),
        ("বিরাশি", 82),
        ("তিরাশি", 83),
        ("চুরাশি", 84),
        ("পঁচাশি", 85),
        ("ছিয়াশি", 86),
        ("ছিয়াশি", 86),
        ("সাতাশি", 87),
        ("অষ্টাশি", 88),
        ("অষ্টআশি", 88),
        ("ঊননব্বই", 89),
        ("উননব্বই", 89),
        ("নব্বই", 90),
        ("একানব্বই", 91),
        ("বিরানব্বই", 92),
        ("তিরানব্বই", 93),
        ("চুরানব্বই", 94),
        ("পঁচানব্বই", 95),
        ("ছিয়ানব্বই", 96),
        ("ছিয়ানব্বই", 96),
        ("সাতানব্বই", 97),
        ("আটানব্বই", 98),
        ("নিরানব্বই", 99),
    ];
    table.iter().copied().collect()
});

/// Half-numbers that only count when a multiplier follows (দেড়শো, আড়াই হাজার).
const HALVES: &[(&str, f64)] = &[("দেড়", 1.5), ("দেড়", 1.5), ("আড়াই", 2.5), ("আড়াই", 2.5)];
const HUNDRED_SUFFIXES: &[&str] = &["শত", "শো", "শ"];
/// Multipliers above a hundred, applied to what came before them.
const MULTIPLIERS: &[(&str, u64)] = &[
    ("হাজার", 1_000),
    ("লক্ষ", 100_000),
    ("লাখ", 100_000),
    ("কোটি", 10_000_000),
];
/// Endings that can stick to the last number word: "বারোটায়" → "১২টায়".
const ATTACHED: &[&str] = &[
    "টায়",
    "টায়",
    "টার",
    "টাই",
    "টা",
    "টির",
    "টি",
    "টে",
    "জনের",
    "জনকে",
    "জন",
];
const PERCENT_WORDS: &[&str] = &["শতাংশ", "পার্সেন্ট", "পারসেন্ট"];
const POINT_WORDS: &[&str] = &["দশমিক", "পয়েন্ট", "পয়েন্ট"];
const HALF_PREFIX: &[&str] = &["সাড়ে", "সাড়ে"];
const FILLERS: &[&str] = &["উম", "উমম", "উম্‌", "আঁ", "অ্যাঁ", "হুম", "হুমম", "এহ", "আহ্‌"];

fn is_punct(c: char) -> bool {
    c.is_ascii_punctuation() || matches!(c, '।' | '॥' | '“' | '”' | '‘' | '’' | '…')
}

/// A token split into leading punctuation, the word, and trailing punctuation.
struct Tok<'a> {
    lead: &'a str,
    word: &'a str,
    trail: &'a str,
}

fn split(token: &str) -> Tok<'_> {
    let start = token.len() - token.trim_start_matches(is_punct).len();
    let end = token.trim_end_matches(is_punct).len().max(start);
    Tok {
        lead: &token[..start],
        word: &token[start..end],
        trail: &token[end..],
    }
}

/// What one word means inside a number.
#[derive(Clone, Copy, Debug)]
enum Part {
    Base(u64),
    Hundreds(f64),
    Half(f64),
    Mult(u64),
}

fn part_of(word: &str) -> Option<Part> {
    if let Some(n) = NUMBERS.get(word) {
        return Some(Part::Base(*n));
    }
    for (w, v) in HALVES {
        if word == *w {
            return Some(Part::Half(*v));
        }
    }
    for (w, m) in MULTIPLIERS {
        if word == *w {
            return Some(Part::Mult(*m));
        }
    }
    for s in HUNDRED_SUFFIXES {
        if let Some(stem) = word.strip_suffix(s) {
            if let Some(n) = NUMBERS.get(stem) {
                return Some(Part::Hundreds(*n as f64));
            }
            for (w, v) in HALVES {
                if stem == *w {
                    return Some(Part::Hundreds(*v));
                }
            }
        }
    }
    None
}

/// The number word and any ending stuck to it.
fn part_with_ending(word: &str) -> Option<(Part, &str)> {
    if let Some(p) = part_of(word) {
        return Some((p, ""));
    }
    for e in ATTACHED {
        if let Some(stem) = word.strip_suffix(e) {
            if let Some(p @ (Part::Base(_) | Part::Hundreds(_) | Part::Mult(_))) = part_of(stem) {
                return Some((p, e));
            }
        }
    }
    None
}

fn digits(n: &str, style: Digits) -> String {
    match style {
        Digits::Latin => n.to_string(),
        Digits::Bengali => n
            .chars()
            .map(|c| match c.to_digit(10) {
                Some(d) => char::from_u32('০' as u32 + d).unwrap_or(c),
                None => c,
            })
            .collect(),
    }
}

/// Indian grouping (১২,৩৪,৫৬৭) from five digits up; four-digit numbers
/// (years, prices) stay ungrouped.
fn group(n: u64) -> String {
    let s = n.to_string();
    if s.len() <= 4 {
        return s;
    }
    let (head, last3) = s.split_at(s.len() - 3);
    let mut parts = Vec::new();
    let mut h = head;
    while h.len() > 2 {
        let (a, b) = h.split_at(h.len() - 2);
        parts.push(b);
        h = a;
    }
    parts.push(h);
    parts.reverse();
    format!("{},{}", parts.join(","), last3)
}

/// Parse the longest number starting at `tokens[i]`. Returns the value, the
/// number of tokens used, whether a multiplier/hundred was involved, and the
/// ending stuck to the last word.
fn parse_number(tokens: &[Tok]) -> Option<(f64, usize, bool, String)> {
    let mut total = 0.0_f64;
    let mut cur = 0.0_f64;
    let mut used = 0;
    let mut scaled = false;
    let mut pending_half = 0.0;
    let mut half_prefix = false;
    let mut ending = String::new();
    for (k, t) in tokens.iter().enumerate() {
        // A number never runs across punctuation inside it.
        if k > 0 && (!tokens[k - 1].trail.is_empty() || !t.lead.is_empty()) {
            break;
        }
        if k == 0 && HALF_PREFIX.contains(&t.word) {
            half_prefix = true;
            used = 1;
            continue;
        }
        let Some((part, end)) = part_with_ending(t.word) else {
            break;
        };
        match part {
            Part::Base(n) => {
                // Two plain numbers in a row ("দুই তিন") are two numbers.
                if cur % 100.0 != 0.0 || pending_half != 0.0 {
                    break;
                }
                cur += n as f64;
            }
            Part::Hundreds(n) => {
                if cur != 0.0 || pending_half != 0.0 {
                    break;
                }
                cur = n * 100.0;
                scaled = true;
            }
            Part::Half(v) => {
                if cur != 0.0 || pending_half != 0.0 {
                    break;
                }
                pending_half = v;
            }
            Part::Mult(m) => {
                let base = if pending_half != 0.0 {
                    pending_half
                } else {
                    cur
                };
                if base == 0.0 {
                    break;
                }
                let base = if half_prefix && cur != 0.0 && pending_half == 0.0 {
                    half_prefix = false;
                    base + 0.5
                } else {
                    base
                };
                total += base * m as f64;
                cur = 0.0;
                pending_half = 0.0;
                scaled = true;
            }
        }
        used = k + 1;
        if !end.is_empty() {
            ending = end.to_string();
            break;
        }
    }
    if pending_half != 0.0 {
        // "দেড়" with nothing to multiply: leave it as a word.
        return None;
    }
    let value = total + cur;
    if value == 0.0 || half_prefix {
        return None;
    }
    Some((value, used, scaled, ending))
}

fn format_value(v: f64, style: Digits) -> String {
    if v.fract() == 0.0 {
        digits(&group(v as u64), style)
    } else {
        digits(&format!("{v}"), style)
    }
}

/// Clean up a Bengali transcript: numbers to digits, percent, decimals, and
/// hesitation sounds removed.
pub fn clean(text: &str, style: Digits, remove_fillers: bool) -> String {
    let raw: Vec<&str> = text.split_whitespace().collect();
    let toks: Vec<Tok> = raw.iter().map(|t| split(t)).collect();
    let mut out: Vec<String> = Vec::with_capacity(raw.len());
    let mut i = 0;
    while i < toks.len() {
        let t = &toks[i];
        if remove_fillers && FILLERS.contains(&t.word) {
            // Keep any punctuation the filler carried, on the previous word.
            if let Some(prev) = out.last_mut() {
                if !t.trail.is_empty() {
                    // A sentence end beats a comma: "আসব, হুম।" → "আসব।".
                    let kept = prev.trim_end_matches(is_punct).len();
                    prev.truncate(kept);
                    prev.push_str(t.trail);
                }
            }
            i += 1;
            continue;
        }
        if let Some((value, used, scaled, ending)) = parse_number(&toks[i..]) {
            let last = &toks[i + used - 1];
            // Decimal: "তিন দশমিক পাঁচ".
            let mut text_val = None;
            let mut extra = 0;
            if ending.is_empty() && last.trail.is_empty() && value.fract() == 0.0 {
                if let Some(p) = toks.get(i + used) {
                    if POINT_WORDS.contains(&p.word) && p.lead.is_empty() && p.trail.is_empty() {
                        let mut frac = String::new();
                        let mut j = i + used + 1;
                        while let Some(d) = toks.get(j) {
                            match NUMBERS.get(d.word).copied().or(if d.word == "শূন্য" {
                                Some(0)
                            } else {
                                None
                            }) {
                                Some(n) if n < 10 => {
                                    frac.push(char::from_digit(n as u32, 10).unwrap())
                                }
                                _ => break,
                            }
                            j += 1;
                            if !toks[j - 1].trail.is_empty() {
                                break;
                            }
                        }
                        if !frac.is_empty() {
                            text_val =
                                Some(digits(&format!("{}.{}", group(value as u64), frac), style));
                            extra = j - (i + used);
                        }
                    }
                }
            }
            let small = value < 10.0 && !scaled && text_val.is_none();
            // Percent: "পঞ্চাশ শতাংশ" → "৫০%".
            let pct_idx = i + used + extra;
            let percent = ending.is_empty()
                && toks[pct_idx - 1].trail.is_empty()
                && toks
                    .get(pct_idx)
                    .is_some_and(|p| PERCENT_WORDS.contains(&p.word) && p.lead.is_empty());
            if small && !percent {
                out.push(raw[i].to_string());
                i += 1;
                continue;
            }
            let num = text_val.unwrap_or_else(|| format_value(value, style));
            let first = &toks[i];
            if percent {
                let p = &toks[pct_idx];
                out.push(format!("{}{}%{}", first.lead, num, p.trail));
                i = pct_idx + 1;
            } else {
                let last = &toks[i + used + extra - 1];
                out.push(format!("{}{}{}{}", first.lead, num, ending, last.trail));
                i += used + extra;
            }
            continue;
        }
        out.push(raw[i].to_string());
        i += 1;
    }
    out.join(" ")
}

#[cfg(test)]
mod tests {
    use super::*;
    const B: Digits = Digits::Bengali;
    const L: Digits = Digits::Latin;

    #[test]
    fn years_and_big_numbers() {
        assert_eq!(
            clean("দুই হাজার সতেরো এর সেপ্টেম্বরে", L, true),
            "2017 এর সেপ্টেম্বরে"
        );
        assert_eq!(clean("উনিশশো একাত্তর সালে", B, true), "১৯৭১ সালে");
        assert_eq!(clean("আট লাখ লাল ফৌজ", L, true), "8,00,000 লাল ফৌজ");
        assert_eq!(clean("এক কোটি বিশ লাখ টাকা", B, true), "১,২০,০০,০০০ টাকা");
        assert_eq!(clean("পাঁচশো টাকা", B, true), "৫০০ টাকা");
        assert_eq!(clean("দেড়শো জন", L, true), "150 জন");
        assert_eq!(clean("আড়াই হাজার", L, true), "2500");
        assert_eq!(clean("সাড়ে তিন হাজার টাকা", L, true), "3500 টাকা");
    }

    #[test]
    fn two_digit_numbers_and_endings() {
        assert_eq!(clean("পঁয়ত্রিশ মিমি", L, true), "35 মিমি");
        assert_eq!(clean("বারোটায় আসবে।", B, true), "১২টায় আসবে।");
        assert_eq!(clean("পনেরো আগস্ট", B, true), "১৫ আগস্ট");
    }

    #[test]
    fn small_numbers_and_lookalikes_stay_words() {
        let s = "বার্লিন সমুদ্রের নিকটবর্তী কোথাও নয় এবং তিনটা আপেল, এক জন লোক।";
        assert_eq!(clean(s, B, true), s);
        assert_eq!(clean("দুই তিন দিন", B, true), "দুই তিন দিন");
        assert_eq!(clean("সাড়ে পাঁচটায়", B, true), "সাড়ে পাঁচটায়");
    }

    #[test]
    fn percent_and_decimals() {
        assert_eq!(clean("পঞ্চাশ শতাংশ মানুষ", B, true), "৫০% মানুষ");
        assert_eq!(clean("তিন দশমিক পাঁচ কেজি", L, true), "3.5 কেজি");
    }

    #[test]
    fn fillers() {
        assert_eq!(clean("উম আমি কাল আসব, হুম।", B, true), "আমি কাল আসব।");
        assert_eq!(clean("উম আমি", B, false), "উম আমি");
    }
}
