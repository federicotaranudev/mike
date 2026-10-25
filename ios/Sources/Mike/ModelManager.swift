import Foundation
import Combine
import CryptoKit

/// Downloads the on-device model file (Gemma 4 E2B, LiteRT-LM .litertlm) from
/// Hugging Face over HTTPS. Anonymous, no account or key needed - the repo is
/// public. The runtime that runs it (LiteRT-LM) ships in v0.4.0+.
/// Integrity: after every download the file's SHA-256 is checked against the
/// publisher's LFS hash before the model counts as usable; a mismatch deletes
/// the file and fails closed. A byte count alone is not enough.
final class ModelManager: NSObject, ObservableObject {
    /// The two published Gemma 4 E2B artifacts. Measured on the CI simulator
    /// (2026-10-25, run 40235669839 and 40234638413): the GPU artifact loads
    /// on Metal in 153-177s and has no CPU path; the base artifact runs on
    /// CPU, loading in ~6s at ~1.1 GB peak RSS, and its GPU delegate fails.
    /// NEITHER is proven on a real iPhone 13 - that uncertainty stays visible
    /// in the Settings copy. The choice is always the user's; Mike never
    /// switches artifacts on its own.
    enum Artifact: String, CaseIterable, Identifiable {
        case gpu, cpu
        var id: String { rawValue }

        var fileName: String {
            switch self {
            case .gpu: return "gemma-4-E2B-it-gpu.litertlm"
            case .cpu: return "gemma-4-E2B-it.litertlm"
            }
        }
        var expectedBytes: Int64 {
            switch self {
            case .gpu: return 2_008_432_640
            case .cpu: return 2_588_147_712
            }
        }
        // SHA-256 published by Hugging Face as each file's LFS oid (and
        // X-Linked-ETag) at repo commit 1caa527c1e88b55f046fcd8d2b4265606680663d.
        // Pinned here so a swapped or truncated file is caught before the
        // runtime ever loads it.
        var sha256: String {
            switch self {
            case .gpu: return "a53a59001894c58e6bdb5b9b227709f91a2e3e556baa7d85acf9c55402ba5cf5"
            case .cpu: return "181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c"
            }
        }
        var url: URL {
            URL(string: "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/\(fileName)")!
        }
        var pickTitle: String {
            switch self {
            case .gpu: return "GPU build (2.0 GB)"
            case .cpu: return "CPU build (2.6 GB)"
            }
        }
        var pickBlurb: String {
            switch self {
            case .gpu:
                return "Runs on the iPhone GPU. First reply loads the model - measured 2.5-3 min on CI hardware. Cannot run on the processor at all. Untested on iPhone 13."
            case .cpu:
                return "Runs on the processor, no GPU needed. In CI it loaded in about 6s and peaked near 1.1 GB memory. Reply speed on an iPhone 13 is untested - it may be slow."
            }
        }
        /// LiteRT-LM backend this artifact needs. Deterministic from the
        /// user's explicit download choice - never inferred at runtime.
        var usesCPU: Bool { self == .cpu }
    }

    enum State: Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case verifying
        case downloaded(bytes: Int64)
        case failed(String)
    }

    @Published private(set) var state: State = .notDownloaded
    /// Which artifact Settings shows and downloads. Persisted; defaults to the
    /// GPU build (the artifact v0.4.x shipped with).
    @Published private(set) var artifact: Artifact {
        didSet { UserDefaults.standard.set(artifact.rawValue, forKey: Self.artifactKey) }
    }

    private static let artifactKey = "mike.model.artifact"
    private static let legacyVerifiedKey = "mike.model.sha256.verified"
    private static func verifiedKey(for a: Artifact) -> String { "mike.model.sha256.verified.\(a.rawValue)" }

    // Backward-compatible constants for the original (GPU) artifact.
    static let modelFileName = Artifact.gpu.fileName
    static let expectedBytes = Artifact.gpu.expectedBytes
    static let expectedSHA256 = Artifact.gpu.sha256
    static let modelURL = Artifact.gpu.url

    private var session: URLSession?
    private var task: URLSessionDownloadTask?

    var modelFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(artifact.fileName)
    }

    override init() {
        let saved = UserDefaults.standard.string(forKey: Self.artifactKey)
        artifact = Artifact(rawValue: saved ?? "") ?? .gpu
        super.init()
        refreshState()
    }

    /// User-visible artifact choice. Allowed any time, but only takes effect
    /// on the next download or state refresh; an in-flight download keeps
    /// writing the artifact it started with.
    func select(_ a: Artifact) {
        guard a != artifact else { return }
        if case .downloading = state { return }  // never swap mid-download
        artifact = a
        refreshState()
    }

    private func refreshState() {
        let url = modelFileURL
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64, size == artifact.expectedBytes else {
            state = .notDownloaded
            return
        }
        let verified = UserDefaults.standard.string(forKey: Self.verifiedKey(for: artifact))
        // The GPU artifact predates per-artifact keys; honor the legacy key.
        let legacyOK = artifact == .gpu &&
            UserDefaults.standard.string(forKey: Self.legacyVerifiedKey) == artifact.sha256
        if verified == artifact.sha256 || legacyOK {
            state = .downloaded(bytes: size)
        } else {
            // File predates hash verification (e.g. downloaded by v0.3.0):
            // verify once in the background instead of trusting the byte count.
            verifyInBackground(existingBytes: size)
        }
    }

    static func freeBytes() -> Int64 {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let v = try? FileManager.default.attributesOfFileSystem(forPath: dir.path)[.systemFreeSize] as? Int64 else { return 0 }
        return v
    }

    static func sha256Hex(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 8 * 1024 * 1024)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func verifyInBackground(existingBytes: Int64) {
        state = .verifying
        let url = modelFileURL
        let a = artifact
        DispatchQueue.global(qos: .userInitiated).async {
            let digest = (try? Self.sha256Hex(of: url)) ?? ""
            DispatchQueue.main.async {
                if digest == a.sha256 {
                    UserDefaults.standard.set(digest, forKey: Self.verifiedKey(for: a))
                    self.state = .downloaded(bytes: existingBytes)
                } else {
                    try? FileManager.default.removeItem(at: url)
                    UserDefaults.standard.removeObject(forKey: Self.verifiedKey(for: a))
                    self.state = .failed("The downloaded file didn't match the publisher's checksum, so it was deleted. Tap download to try again.")
                }
            }
        }
    }

    func startDownload() {
        let a = artifact
        // Need the file plus breathing room; refuse early instead of filling the phone.
        guard Self.freeBytes() > a.expectedBytes + 600_000_000 else {  // file + working room
            state = .failed("Not enough free space. The model needs about \(String(format: "%.1f", Double(a.expectedBytes) / 1e9 + 0.6)) GB free; delete it later from here if you change your mind.")
            return
        }
        state = .downloading(progress: 0)
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForResource = 60 * 60 * 3
        let s = URLSession(configuration: cfg, delegate: self, delegateQueue: OperationQueue.main)
        session = s
        task = s.downloadTask(with: a.url)
        task?.resume()
    }

    func cancelDownload() {
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        state = .notDownloaded
    }

    func deleteModel() {
        try? FileManager.default.removeItem(at: modelFileURL)
        UserDefaults.standard.removeObject(forKey: Self.verifiedKey(for: artifact))
        UserDefaults.standard.removeObject(forKey: Self.legacyVerifiedKey)
        state = .notDownloaded
    }
}

extension ModelManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        state = .downloading(progress: Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        do {
            if FileManager.default.fileExists(atPath: modelFileURL.path) {
                try FileManager.default.removeItem(at: modelFileURL)
            }
            try FileManager.default.moveItem(at: location, to: modelFileURL)
            let size = (try? FileManager.default.attributesOfItem(atPath: modelFileURL.path)[.size] as? Int64) ?? 0
            guard size == artifact.expectedBytes else {
                try? FileManager.default.removeItem(at: modelFileURL)
                state = .failed("The download was incomplete (\(size) of \(artifact.expectedBytes) bytes). Tap download to try again.")
                return
            }
            verifyInBackground(existingBytes: size)
        } catch {
            state = .failed("Couldn't store the file: \(error.localizedDescription)")
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error else { return }
        if (error as NSError).code == NSURLErrorCancelled { return }
        state = .failed("Download stopped: \(error.localizedDescription). Tap download to try again.")
    }
}
