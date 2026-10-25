import Foundation

/// Talks to the agent core on the user's own PC over the tunnel URL the user
/// sets in Settings. No third-party servers: the phone talks to his PC only.
final class APIClient: ObservableObject {
    @Published var baseURL: URL? {
        didSet { UserDefaults.standard.set(baseURL?.absoluteString, forKey: "mike.baseURL") }
    }
    /// Shared secret the core requires once it leaves 127.0.0.1 (MIKE_TOKEN).
    @Published var token: String {
        didSet { UserDefaults.standard.set(token, forKey: "mike.token") }
    }
    @Published var lastError: String?

    init() {
        if let s = UserDefaults.standard.string(forKey: "mike.baseURL") { baseURL = URL(string: s) }
        token = UserDefaults.standard.string(forKey: "mike.token") ?? ""
    }

    private func request(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        guard let baseURL else { throw URLError(.badURL) }
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
        let (data, resp) = try await URLSession.shared.data(for: req)
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
