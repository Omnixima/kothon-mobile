// A model download that survives a shaky connection. Bytes go into a
// `.part` file next to the destination; when the connection drops, the next
// attempt asks the server for the rest (HTTP Range) instead of starting over.
// The `.part` file stays on disk, so tapping ডাউনলোড again later continues too.

import Foundation
import UIKit

enum ResumableDownload {
    /// Attempts per file before giving up and showing the error.
    static let attempts = 6

    /// Download `remote` to `local`, retrying network failures with backoff.
    /// `onProgress` gets the fraction of the whole file, including bytes from
    /// earlier attempts.
    static func fetch(_ remote: URL, to local: URL,
                      onProgress: @escaping @Sendable (Double) -> Void) async throws {
        let part = local.appendingPathExtension("part")
        try await withRetries {
            try await Attempt(remote: remote, part: part, onProgress: onProgress).run()
        }
        try? FileManager.default.removeItem(at: local)
        try FileManager.default.moveItem(at: part, to: local)
    }

    /// Run `body` up to `attempts` times while it fails with a network error,
    /// waiting 2, 4, 8, 16, 30 s in between. Other errors fail at once.
    /// `retryAny` retries every error but cancellation (for libraries whose
    /// errors don't say whether the network was at fault).
    static func withRetries<T>(retryAny: Bool = false, _ body: () async throws -> T) async throws -> T {
        try await keepingAppAwake {
            var attempt = 1
            while true {
                do {
                    return try await body()
                } catch {
                    let retry = retryAny ? !(error is CancellationError) : isTransient(error)
                    guard attempt < attempts, retry, !Task.isCancelled else { throw error }
                    let wait = min(30, 1 << attempt)
                    try await Task.sleep(nanoseconds: UInt64(wait) * 1_000_000_000)
                    attempt += 1
                }
            }
        }
    }

    /// Errors worth another try: the connection dropped, timed out or wasn't
    /// there, or the server had a temporary problem.
    static func isTransient(_ error: Error) -> Bool {
        if let http = error as? HTTPStatusError { return http.code >= 500 || http.code == 429 }
        let ns = error as NSError
        guard ns.domain == NSURLErrorDomain else {
            // WhisperKit and the Hub library wrap URL errors.
            if let inner = ns.userInfo[NSUnderlyingErrorKey] as? Error { return isTransient(inner) }
            return "\(error)".contains("NSURLErrorDomain")
        }
        return ns.code != NSURLErrorCancelled
            && ns.code != NSURLErrorBadURL
            && ns.code != NSURLErrorUnsupportedURL
    }

    /// Ask iOS for extra time if the person leaves the app mid-download, and
    /// keep the screen from locking while it runs.
    @MainActor private static var activeDownloads = 0

    private static func keepingAppAwake<T>(_ body: () async throws -> T) async throws -> T {
        let task = await MainActor.run { () -> UIBackgroundTaskIdentifier in
            activeDownloads += 1
            UIApplication.shared.isIdleTimerDisabled = true
            var id = UIBackgroundTaskIdentifier.invalid
            id = UIApplication.shared.beginBackgroundTask(withName: "model-download") {
                UIApplication.shared.endBackgroundTask(id)
                id = .invalid
            }
            return id
        }
        defer {
            Task { @MainActor in
                activeDownloads -= 1
                if activeDownloads == 0 { UIApplication.shared.isIdleTimerDisabled = false }
                if task != .invalid { UIApplication.shared.endBackgroundTask(task) }
            }
        }
        return try await body()
    }
}

struct HTTPStatusError: LocalizedError {
    let code: Int
    var errorDescription: String? { "ডাউনলোড ব্যর্থ (\(code))" }
}

/// One attempt: request the bytes the `.part` file doesn't have yet and
/// append them as they arrive.
private final class Attempt: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let remote: URL
    let part: URL
    let onProgress: @Sendable (Double) -> Void

    private var handle: FileHandle?
    private var written: Int64 = 0
    private var total: Int64 = 0
    private var continuation: CheckedContinuation<Void, Error>?
    private var failure: Error?

    init(remote: URL, part: URL, onProgress: @escaping @Sendable (Double) -> Void) {
        self.remote = remote
        self.part = part
        self.onProgress = onProgress
    }

    func run() async throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: part.path) { fm.createFile(atPath: part.path, contents: nil) }
        let have = ((try? fm.attributesOfItem(atPath: part.path)[.size]) as? NSNumber)?.int64Value ?? 0

        var request = URLRequest(url: remote)
        if have > 0 { request.setValue("bytes=\(have)-", forHTTPHeaderField: "Range") }
        let config = URLSessionConfiguration.default
        // Give up on a stalled connection after a minute, then retry.
        config.timeoutIntervalForRequest = 60
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                continuation = c
                written = have
                session.dataTask(with: request).resume()
            }
        } onCancel: {
            session.invalidateAndCancel()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        do {
            let h = try FileHandle(forWritingTo: part)
            switch status {
            case 206:
                // The rest of the file: append. Content-Range is "bytes a-b/total".
                try h.seekToEnd()
                let range = http?.value(forHTTPHeaderField: "Content-Range") ?? ""
                total = Int64(range.split(separator: "/").last ?? "") ?? (written + response.expectedContentLength)
            case 200:
                // The server sent the whole file: start the .part over.
                try h.truncate(atOffset: 0)
                written = 0
                total = response.expectedContentLength
            case 416:
                // Nothing left to send, or the .part is bad: start over next try.
                try h.truncate(atOffset: 0)
                try? h.close()
                failure = URLError(.networkConnectionLost)
                completionHandler(.cancel)
                return
            default:
                try? h.close()
                failure = HTTPStatusError(code: status)
                completionHandler(.cancel)
                return
            }
            handle = h
            report()
            completionHandler(.allow)
        } catch {
            failure = error
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            try handle?.write(contentsOf: data)
            written += Int64(data.count)
            report()
        } catch {
            failure = error
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? handle?.synchronize()
        try? handle?.close()
        handle = nil
        let c = continuation
        continuation = nil
        if let failure {
            c?.resume(throwing: failure)
        } else if let error {
            c?.resume(throwing: error)
        } else if total > 0 && written < total {
            // The server closed early: retry for the rest.
            c?.resume(throwing: URLError(.networkConnectionLost))
        } else {
            c?.resume()
        }
    }

    private var lastReport = Date.distantPast

    private func report() {
        guard total > 0 else { return }
        let now = Date()
        // A few updates a second is plenty for the progress ring.
        guard now.timeIntervalSince(lastReport) > 0.2 || written >= total else { return }
        lastReport = now
        onProgress(min(1, Double(written) / Double(total)))
    }
}
