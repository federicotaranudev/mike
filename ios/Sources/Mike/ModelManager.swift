import Foundation
import Combine
import CryptoKit

/// Downloads the on-device model file (Gemma 4 E2B, LiteRT-LM .litertlm) from
/// Hugging Face over HTTPS. Anonymous, no account or key needed - the repo is
/// public. The runtime that runs it (LiteRT-LM, Metal GPU) ships in v0.4.0+.
/// Integrity: after every download the file's SHA-256 is checked against the
/// publisher's LFS hash before the model counts as usable; a mismatch deletes
/// the file and fails closed. A byte count alone is not enough.
final class ModelManager: NSObject, ObservableObject {
    enum State: Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case verifying
        case downloaded(bytes: Int64)
        case failed(String)
    }

    @Published private(set) var state: State = .notDownloaded

    static let modelFileName = "gemma-4-E2B-it-gpu.litertlm"
    static let expectedBytes: Int64 = 2_008_432_640
    // SHA-256 published by Hugging Face as the file's LFS oid (and X-Linked-ETag)
    // at repo commit 1caa527c1e88b55f046fcd8d2b4265606680663d. Pinned here so a
    // swapped or truncated file is caught before the runtime ever loads it.
    static let expectedSHA256 = "a53a59001894c58e6bdb5b9b227709f91a2e3e556baa7d85acf9c55402ba5cf5"
    static let modelURL = URL(string: "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it-gpu.litertlm")!
    private static let verifiedKey = "mike.model.sha256.verified"

    private var session: URLSession?
    private var task: URLSessionDownloadTask?

    var modelFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Self.modelFileName)
    }

    override init() {
        super.init()
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: modelFileURL.path),
              let size = attrs[.size] as? Int64, size == Self.expectedBytes else { return }
        if UserDefaults.standard.string(forKey: Self.verifiedKey) == Self.expectedSHA256 {
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
        DispatchQueue.global(qos: .userInitiated).async {
            let digest = (try? Self.sha256Hex(of: url)) ?? ""
            DispatchQueue.main.async {
                if digest == Self.expectedSHA256 {
                    UserDefaults.standard.set(digest, forKey: Self.verifiedKey)
                    self.state = .downloaded(bytes: existingBytes)
                } else {
                    try? FileManager.default.removeItem(at: url)
                    UserDefaults.standard.removeObject(forKey: Self.verifiedKey)
                    self.state = .failed("The downloaded file didn't match the publisher's checksum, so it was deleted. Tap download to try again.")
                }
            }
        }
    }

    func startDownload() {
        // Need the file plus breathing room; refuse early instead of filling the phone.
        guard Self.freeBytes() > Self.expectedBytes + 600_000_000 else {  // file + working room
            state = .failed("Not enough free space. The model needs about 2.6 GB free; delete it later from here if you change your mind.")
            return
        }
        state = .downloading(progress: 0)
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForResource = 60 * 60 * 3
        let s = URLSession(configuration: cfg, delegate: self, delegateQueue: OperationQueue.main)
        session = s
        task = s.downloadTask(with: Self.modelURL)
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
        UserDefaults.standard.removeObject(forKey: Self.verifiedKey)
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
            guard size == Self.expectedBytes else {
                try? FileManager.default.removeItem(at: modelFileURL)
                state = .failed("The download was incomplete (\(size) of \(Self.expectedBytes) bytes). Tap download to try again.")
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
