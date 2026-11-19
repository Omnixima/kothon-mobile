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

    static let all = [fast, accurate]
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
        FileManager.default.fileExists(atPath: file(for: model).path)
    }

    var punctuationDir: URL { dir.appendingPathComponent(PunctuationModel.dirName, isDirectory: true) }
    var punctuationInstalled: Bool {
        FileManager.default.fileExists(atPath: punctuationDir.appendingPathComponent("model.safetensors").path)
    }

    func isDownloading(_ id: String) -> Bool { progress[id] != nil }

    func download(_ model: SpeechModel) async {
        await fetch(id: model.id, items: [(model.url, file(for: model))])
    }

    func downloadPunctuation() async {
        try? FileManager.default.createDirectory(at: punctuationDir, withIntermediateDirectories: true)
        let items = PunctuationModel.files.map {
            (URL(string: "\(PunctuationModel.base)/\($0)")!, punctuationDir.appendingPathComponent($0))
        }
        await fetch(id: PunctuationModel.dirName, items: items)
    }

    func delete(_ model: SpeechModel) {
        try? FileManager.default.removeItem(at: file(for: model))
        objectWillChange.send()
    }

    private func fetch(id: String, items: [(URL, URL)]) async {
        guard progress[id] == nil else { return }
        progress[id] = 0
        lastError = nil
        defer { progress[id] = nil }
        do {
            for (index, (remote, local)) in items.enumerated() {
                let (tmp, response) = try await URLSession.shared.download(
                    from: remote,
                    delegate: ProgressDelegate { [weak self] fraction in
                        Task { @MainActor in
                            self?.progress[id] = (Double(index) + fraction) / Double(items.count)
                        }
                    })
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw EngineError(message: "ডাউনলোড ব্যর্থ (\((response as? HTTPURLResponse)?.statusCode ?? 0))")
                }
                try? FileManager.default.removeItem(at: local)
                try FileManager.default.moveItem(at: tmp, to: local)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }
}

private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate {
    let onProgress: (Double) -> Void
    init(_ onProgress: @escaping (Double) -> Void) { self.onProgress = onProgress }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData _: Int64, totalBytesWritten written: Int64,
                    totalBytesExpectedToWrite total: Int64) {
        if total > 0 { onProgress(Double(written) / Double(total)) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {}
}
