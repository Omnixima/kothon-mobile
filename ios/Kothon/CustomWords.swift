// "আমার শব্দ": names and English words the model gets wrong, fixed with
// "শুনলে → লিখুন" pairs applied to the finished text, for every model, on
// whole words. A Bengali case ending after the word is kept:
// "আইএ এসের" → "iOS-এর".
//
// A Whisper prompt with these words was tried and dropped: the Bengali
// fine-tune then writes almost nothing (WER 8.1% → 96.8% on FLEURS; see
// kothon-coreml REPORT.md).

import Foundation

struct Replacement: Codable, Hashable, Identifiable {
    var heard: String
    var write: String
    var id: String { heard + "→" + write }
}

enum CustomWords {
    private static let replacementsKey = "customReplacements"

    static let builtInReplacements = [
        Replacement(heard: "আইএ এস", write: "iOS"),
        Replacement(heard: "আইওএস", write: "iOS"),
        Replacement(heard: "আই ও এস", write: "iOS"),
        Replacement(heard: "আইফোন", write: "iPhone"),
        Replacement(heard: "হোয়াটসঅ্যাপ", write: "WhatsApp"),
        Replacement(heard: "অমনিক্সিমা", write: "Omnixima"),
        Replacement(heard: "কথা অ্যাপ", write: "কথন অ্যাপ"),
        Replacement(heard: "এন্ড্রয়েড", write: "Android"),
    ]

    static var replacements: [Replacement] {
        get {
            guard let data = UserDefaults.standard.data(forKey: replacementsKey),
                  let list = try? JSONDecoder().decode([Replacement].self, from: data) else { return builtInReplacements }
            return list
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: replacementsKey) }
    }

    /// Bengali case endings kept after a replaced word, written after a hyphen.
    private static let endings: [(heard: String, write: String)] = [
        ("য়ের", "এর"), ("ের", "এর"), ("এর", "এর"), ("কে", "কে"), ("তে", "তে"), ("ে", "এ"), ("এ", "এ"), ("র", "এর"),
    ]

    /// Apply the replacements on whole words.
    static func apply(_ text: String) -> String {
        var out = text
        for r in replacements where !r.heard.isEmpty {
            let heard = NSRegularExpression.escapedPattern(for: r.heard)
            let ends = endings.map { NSRegularExpression.escapedPattern(for: $0.heard) }.joined(separator: "|")
            let pattern = "(?<![\\p{L}\\p{M}\\p{N}])\(heard)(\(ends))?(?![\\p{L}\\p{M}\\p{N}])"
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = out as NSString
            var result = ""
            var last = 0
            for m in re.matches(in: out, range: NSRange(location: 0, length: ns.length)) {
                result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                result += r.write
                if m.range(at: 1).location != NSNotFound {
                    let ending = ns.substring(with: m.range(at: 1))
                    let written = endings.first { $0.heard == ending }?.write ?? ending
                    // A Latin word takes a hyphen before the Bengali ending; a Bengali one doesn't.
                    result += (r.write.unicodeScalars.last.map { $0.isASCII } ?? false) ? "-" + written : ending
                }
                last = m.range.location + m.range.length
            }
            result += ns.substring(from: last)
            out = result
        }
        return out
    }
}
