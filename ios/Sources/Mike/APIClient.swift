import Foundation

/// Fail-closed network rules shared by all clients: HTTPS only, and redirects
/// to a different host are refused so a Bearer token or API key can never leak
/// to a host we did not configure.
enum RedirectPolicy {
    static func allowed(newRequest: URLRequest, originalHost: String?) -> Bool {
        guard let url = newRequest.url, url.scheme == "https", url.host == originalHost else { return false }
        return true
    }
}

final class SameHostOnlySession: NSObject, URLSessionDelegate {
    let originalHost: String?
    init(originalHost: String?) { self.originalHost = originalHost }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(RedirectPolicy.allowed(newRequest: request, originalHost: originalHost) ? request : nil)
    }
}

/// Talks to a backend the user configured in Settings: a Mike core they run
/// themselves. The URL is not a secret (UserDefaults); the token lives in the
/// iPhone Keychain only.
final class APIClient: ObservableObject {
    @Published var baseURL: URL? {
        didSet { UserDefaults.standard.set(baseURL?.absoluteString, forKey: "mike.baseURL") }
    }
    /// Shared secret the backend requires once it leaves 127.0.0.1. Read from
    /// the Keychain on every request; never written to UserDefaults or logs.
    private var token: String { KeychainStore.load(KeychainStore.backendToken) ?? "" }
    @Published var lastError: String?

    init() {
        if let s = UserDefaults.standard.string(forKey: "mike.baseURL") { baseURL = URL(string: s) }
    }

    private func request(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        guard let baseURL else { throw URLError(.badURL) }
        // Fail closed: the backend token must never travel over plain HTTP,
        // no matter what is stored.
        guard baseURL.scheme == "https" else { throw URLError(.unsupportedURL) }
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.timeoutInterval = 20
        if !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let session = URLSession(configuration: .ephemeral,
                                 delegate: SameHostOnlySession(originalHost: baseURL.host),
                                 delegateQueue: nil)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    func sendChat(_ text: String) async throws -> String {
        struct Out: Codable { let reply: String }
        let payload = try JSONEncoder().encode(["message": text])
        let data = try await request("chat", method: "POST", body: payload)
        return try JSONDecoder().decode(Out.self, from: data).reply
    }

    func pendingApprovals() async throws -> [Approval] {
        try JSONDecoder().decode([Approval].self, from: try await request("approvals/pending"))
    }

    func answer(_ approval: Approval, approve: Bool) async throws {
        let payload = try JSONEncoder().encode(["approve": approve])
        _ = try await request("approvals/\(approval.id)", method: "POST", body: payload)
    }

    func activity() async throws -> [ActivityEntry] {
        try JSONDecoder().decode([ActivityEntry].self, from: try await request("activity"))
    }

    func status() async throws -> CoreStatus {
        try JSONDecoder().decode(CoreStatus.self, from: try await request("status"))
    }

    func stopMike() async throws {
        _ = try await request("stop", method: "POST")
    }
}
