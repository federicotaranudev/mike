import Foundation
import Combine

/// Downloads the on-device model file (Gemma 4 E2B, Q4_0 GGUF) from Hugging
/// Face over HTTPS. Anonymous, no account or key needed - the repo is public.
/// IMPORTANT honest state: this downloads the WEIGHTS only. The runtime that
/// runs them (llama.cpp) is not in this build yet; the UI says so plainly.
final class ModelManager: NSObject, ObservableObject {
    enum State: Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case downloaded(bytes: Int64)
        case failed(String)
    }

    @Published private(set) var state: State = .notDownloaded

    static let modelFileName = "gemma-4-E2B-it-Q4_0.gguf"
    static let expectedBytes: Int64 = 2_841_481_184
    static let modelURL = URL(string: "https://huggingface.co/ggml-org/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_0.gguf")!

    private var session: URLSession?
    private var task: URLSessionDownloadTask?

    var modelFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Self.modelFileName)
    }

    override init() {
        super.init()
        if let attrs = try? FileManager.default.attributesOfItem(atPath: modelFileURL.path),
           let size = attrs[.size] as? Int64, size == Self.expectedBytes {
            state = .downloaded(bytes: size)
        }
    }

    static func freeBytes() -> Int64 {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let v = try? FileManager.default.attributesOfFileSystem(forPath: dir.path)[.systemFreeSize] as? Int64 else { return 0 }
        return v
    }

    func startDownload() {
        // Need the file plus breathing room; refuse early instead of filling the phone.
        guard Self.freeBytes() > Self.expectedBytes + 600_000_000 else {
            state = .failed("Not enough free space. The model needs about 3.4 GB free; delete it later from here if you change your mind.")
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
            state = .downloaded(bytes: size)
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
