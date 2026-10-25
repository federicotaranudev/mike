import Foundation

/// Talks to Groq's OpenAI-compatible API directly from this phone, using the
/// key the user typed into the app. The key comes from the Keychain and is
/// never logged or sent anywhere but api.groq.com.
enum GroqClient {
    struct ModelsResponse: Codable { let data: [ModelID] }
    struct ModelID: Codable { let id: String }
    struct ChatRequest: Encodable { let model: String; let messages: [Msg] }
    struct Msg: Codable { let role: String; let content: String }
    struct ChatResponse: Codable { let choices: [Choice] }
    struct Choice: Codable { let message: Msg }
    struct ErrorBody: Codable { let error: Err }
    struct Err: Codable { let message: String }

    /// Real check against Groq's model list. Returns a human-readable verdict.
    static func validate(key: String) async -> String {
        var req = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/models")!)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 20
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return "No response from Groq." }
            if http.statusCode == 401 { return "Groq rejected that key. Check it and try again." }
            guard (200..<300).contains(http.statusCode),
                  let models = try? JSONDecoder().decode(ModelsResponse.self, from: data) else {
                return "Groq answered with status \(http.statusCode). The key is not verified."
            }
            let ids = models.data.map { $0.id }
            UserDefaults.standard.set(ids, forKey: "mike.groqModels")
            let preferred = ids.first { $0.contains("llama") } ?? ids.first
            UserDefaults.standard.set(preferred, forKey: "mike.groqModel")
            return "Key works. \(ids.count) models available; chat will use \(preferred ?? "the default")."
        } catch {
            return "Couldn't reach Groq: \(error.localizedDescription)"
        }
    }

    static func chat(key: String, history: [Msg]) async throws -> String {
        let model = UserDefaults.standard.string(forKey: "mike.groqModel") ?? "llama-3.3-70b-versatile"
        var req = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(ChatRequest(model: model, messages: history))
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            if let body = try? JSONDecoder().decode(ErrorBody.self, from: data) {
                throw NSError(domain: "Groq", code: http.statusCode,
                              userInfo: [NSLocalizedDescriptionKey: "Groq said: \(body.error.message)"])
            }
            throw NSError(domain: "Groq", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "Groq answered with status \(http.statusCode)."])
        }
        let out = try JSONDecoder().decode(ChatResponse.self, from: data)
        return out.choices.first?.message.content ?? "(Groq returned an empty reply.)"
    }
}
