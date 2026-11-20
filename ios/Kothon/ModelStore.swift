// Downloads Kothon's models from Hugging Face (huggingface.co/omnixima) once,
// into the app's Application Support folder. Nothing else leaves the phone.

import Foundation

struct SpeechModel: Identifiable, Equatable {
    let id: String
    let label: String
    let detail: String
    let repo: String
    let filename: String
    let sizeMB: Int
    let noTimestamps: Bool
    /// Core ML (WhisperKit) model folder on Hugging Face, for the Neural
    /// Engine. `nil` for GGUF models run by kothon-core.
    var coreML: (repo: String, variant: String)? = nil

    var isCoreML: Bool { coreML != nil }

    static func == (a: SpeechModel, b: SpeechModel) -> Bool { a.id == b.id }

    var url: URL { URL(string: "https://huggingface.co/\(repo)/resolve/main/\(filename)")! }

    /// Same models as the desktop app (src-tauri/src/kothon.rs).
    static let fast = SpeechModel(
        id: "kothon-bn-fastconformer-116m", label: "দ্রুত",
        detail: "FastConformer ১১৬M · ১৩২ MB",
        repo: "omnixima/bangla-fastconformer-ctc-116m-gguf",
        filename: "bangla-fastconformer-ctc-116m-Q8_0.gguf", sizeMB: 132, noTimestamps: false)

    static let accurate = SpeechModel(
        id: "kothon-bn-whisper-medium", label: "নিখুঁত",
        detail: "Whisper Medium · ৭৯৩ MB · নতুন ফোনের জন্য",
        repo: "omnixima/bengaliai-whisper-medium-gguf",
        filename: "bengali-whisper-medium-Q8_0.gguf", sizeMB: 793, noTimestamps: true)

    /// নিখুঁত converted to Core ML, for the Neural Engine. The only way to
    /// run it fast from the keyboard: iOS keeps the GPU from background apps.
    /// 6-bit palettized weights (557 MB); same accuracy as the GGUF on 200
    /// FLEURS clips (8.1% WER vs 8.2%).
    static let accurateNeuralEngine = SpeechModel(
        id: "kothon-bn-whisper-medium-coreml", label: "নিখুঁত (Neural Engine)",
        detail: "Whisper Medium · Core ML · ৫৫৭ MB · কিবোর্ড থেকেও দ্রুত",
        repo: "omnixima/bengaliai-whisper-medium-coreml", filename: "", sizeMB: 560, noTimestamps: true,
        coreML: (repo: "omnixima/bengaliai-whisper-medium-coreml", variant: "bengaliai-whisper-medium"))

    static let all = [fast, accurate, accurateNeuralEngine]
}

/// The punctuation model's files (desktop: src-tauri/src/kothon_punct.rs).
enum PunctuationModel {
    static let dirName = "bn-punct-muril6"
    static let base = "https://huggingface.co/omnixima/bangla-punctuation-muril6/resolve/main"
    /// Weights last: their presence marks the model as installed.
    static let files = ["config.json", "tokenizer.json", "model.safetensors"]
    static let sizeMB = 128
}

@MainActor
final class ModelStore: ObservableObject {
    static let shared = ModelStore()

    @Published private(set) var progress: [String: Double] = [:]
    @Published private(set) var lastError: String?
    @Published var selectedID: String {
        didSet { UserDefaults.standard.set(selectedID, forKey: "selectedModel") }
    }

    let dir: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = support.appendingPathComponent("models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Models are re-downloadable: keep them out of iCloud backups.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var d = dir
        try? d.setResourceValues(values)
        selectedID = UserDefaults.standard.string(forKey: "selectedModel") ?? SpeechModel.fast.id
    }

    var selected: SpeechModel { SpeechModel.all.first { $0.id == selectedID } ?? .fast }

    func file(for model: SpeechModel) -> URL { dir.appendingPathComponent(model.filename) }
    func isInstalled(_ model: SpeechModel) -> Bool {
        if model.isCoreML { return coreMLFolder(for: model) != nil }
        return FileManager.default.fileExists(atPath: file(for: model).path)
    }

    /// Where WhisperKit put a Core ML model, once downloaded.
    func coreMLFolder(for model: SpeechModel) -> URL? {
        // A copy placed in Documents (e.g. with `xcrun devicectl device copy
        // to`) counts too, for testing before the model is on Hugging Face.
        if let variant = model.coreML?.variant {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(variant, isDirectory: true)
            if FileManager.default.fileExists(atPath: docs.appendingPathComponent("TextDecoder.mlmodelc").path) {
                return docs
            }
        }
        guard let path = UserDefaults.standard.string(forKey: "coreml.\(model.id)"),
              FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    var punctuationDir: URL { dir.appendingPathComponent(PunctuationModel.dirName, isDirectory: true) }
    var punctuationInstalled: Bool {
        FileManager.default.fileExists(atPath: punctuationDir.appendingPathComponent("model.safetensors").path)
    }

    func isDownloading(_ id: String) -> Bool { progress[id] != nil }

    /// Free space the system will give us, in bytes.
    /// Free space, in MB, for the setup screen.
    var freeMB: Int? { freeBytes().map { Int($0 / 1_000_000) } }

    /// Space a model needs on this phone (a Core ML one also needs room for
    /// the Neural Engine compile cache).
    static func neededMB(_ model: SpeechModel) -> Int {
        model.isCoreML ? Int(Double(model.sizeMB) * 2.5) : model.sizeMB + 200
    }

    /// Why this model can't be downloaded now, or nil if it can.
    func roomProblem(_ model: SpeechModel) -> String? {
        guard let free = freeMB else { return nil }
        let short = Self.neededMB(model) - free
        guard short > 0 else { return nil }
        let gb = max(0.1, (Double(short) / 1000 * 10).rounded(.up) / 10)
        return "জায়গা কম: আরও \(DictationService.bn(gb)) GB খালি করুন"
    }

    /// iPhone 12 and older (A14 and earlier). Their Neural Engine can't
    /// compile নিখুঁত's encoder: on an iPhone 12 Pro Max the compile gave up
    /// after 6–7 minutes and restarted, again and again.
    static let olderChip: Bool = {
        var info = utsname()
        uname(&info)
        // The simulator reports the Mac; it names the simulated iPhone here.
        let hardware: String = withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        let machine: String = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? hardware
        // "iPhone13,4" → 13. iPhone13,x is the A14; iPhone14,x the A15.
        guard machine.hasPrefix("iPhone"),
              let major = Int(machine.dropFirst("iPhone".count).split(separator: ",").first ?? "") else { return false }
        return major <= 13
    }()

    /// What we suggest. On current iPhones, নিখুঁত on the Neural Engine is
    /// the most accurate and stays fast from the keyboard (iOS keeps the GPU
    /// from background apps). On older ones, দ্রুত.
    static var recommended: SpeechModel { olderChip ? .fast : .accurateNeuralEngine }

    /// The নিখুঁত this phone should use: the Neural Engine one, or on older
    /// phones the GGUF one (GPU in the app, CPU from the keyboard).
    static var accurateForThisPhone: SpeechModel { olderChip ? .accurate : .accurateNeuralEngine }

    private func freeBytes() -> Int64? {
        let values = try? dir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    /// Refuse a download that wouldn't fit. A Core ML model also needs room
    /// for the Neural Engine compile that iOS caches on its first load
    /// (about 1.5× the model); without it, every load compiles from scratch.
    private func hasRoom(forMB sizeMB: Int, coreML: Bool) -> Bool {
        let neededMB = coreML ? Int(Double(sizeMB) * 2.5) : sizeMB + 200
        guard let free = freeBytes() else { return true }
        let shortMB = neededMB - Int(free / 1_000_000)
        if shortMB <= 0 { return true }
        let gb = max(0.1, (Double(shortMB) / 1000 * 10).rounded(.up) / 10)
        lastError = "ফোনে যথেষ্ট জায়গা নেই: আরও \(DictationService.bn(gb)) GB খালি করুন"
        return false
    }

    func download(_ model: SpeechModel) async {
        lastError = nil
        guard hasRoom(forMB: model.sizeMB, coreML: model.isCoreML) else { return }
        if let coreML = model.coreML {
            guard progress[model.id] == nil else { return }
            progress[model.id] = 0
            lastError = nil
            defer { progress[model.id] = nil }
            do {
                // The Hub library keeps partial files and resumes them, so a
                // retry continues where the dropped connection stopped.
                let dir = self.dir
                let folder = try await ResumableDownload.withRetries(retryAny: true) {
                    try await NeuralEngineModels.download(
                        repo: coreML.repo, variant: coreML.variant, into: dir
                    ) { [weak self] fraction in
                        Task { @MainActor in
                            // Never jump back while a retry recounts.
                            let now = self?.progress[model.id] ?? 0
                            self?.progress[model.id] = max(now, fraction)
                        }
                    }
                }
                UserDefaults.standard.set(folder.path, forKey: "coreml.\(model.id)")
            } catch {
                lastError = error.localizedDescription
            }
            return
        }
        await fetch(id: model.id, items: [(model.url, file(for: model))])
    }

    func downloadPunctuation() async {
        lastError = nil
        guard hasRoom(forMB: PunctuationModel.sizeMB, coreML: false) else { return }
        try? FileManager.default.createDirectory(at: punctuationDir, withIntermediateDirectories: true)
        let items = PunctuationModel.files.map {
            (URL(string: "\(PunctuationModel.base)/\($0)")!, punctuationDir.appendingPathComponent($0))
        }
        await fetch(id: PunctuationModel.dirName, items: items)
    }

    /// Remove a downloaded model to free space. It can be downloaded again.
    func delete(_ model: SpeechModel) {
        let fm = FileManager.default
        if let variant = model.coreML?.variant {
            // The copy WhisperKit downloaded, and a test copy in Documents.
            if let path = UserDefaults.standard.string(forKey: "coreml.\(model.id)") {
                try? fm.removeItem(atPath: path)
                UserDefaults.standard.removeObject(forKey: "coreml.\(model.id)")
            }
            let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try? fm.removeItem(at: docs.appendingPathComponent(variant, isDirectory: true))
        } else {
            try? fm.removeItem(at: file(for: model))
        }
        if selectedID == model.id {
            selectedID = SpeechModel.all.first { $0.id != model.id && isInstalled($0) }?.id ?? SpeechModel.fast.id
        }
        objectWillChange.send()
    }

    func deletePunctuation() {
        try? FileManager.default.removeItem(at: punctuationDir)
        objectWillChange.send()
    }

    private func fetch(id: String, items: [(URL, URL)]) async {
        guard progress[id] == nil else { return }
        progress[id] = 0
        lastError = nil
        defer { progress[id] = nil }
        do {
            for (index, (remote, local)) in items.enumerated() {
                try await ResumableDownload.fetch(remote, to: local) { [weak self] fraction in
                    Task { @MainActor in
                        self?.progress[id] = (Double(index) + fraction) / Double(items.count)
                    }
                }
            }
        } catch {
            lastError = error.localizedDescription
        }
    }
}
