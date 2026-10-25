import Foundation

/// Talks to Groq's OpenAI-compatible API directly from this phone, using the
/// key the user typed into the app. The key comes from the Keychain and is
/// never logged or sent anywhere but api.groq.com.
enum GroqClient {
    struct ModelsResponse: Codable { let data: [ModelID] }
    struct ModelID: Codable { let id: String }
    struct ChatRequest: Encodable { let model: String; let messages: [Msg]; let max_tokens: Int }
    struct Msg: Codable { let role: String; let content: String }
    struct ChatResponse: Codable { let choices: [Choice] }
    struct Choice: Codable { let message: Msg }
    struct ErrorBody: Codable { let error: Err }
    struct Err: Codable { let message: String }

    /// Model ids that are NOT chat models (classifiers, guardrails, audio,
    /// embeddings). v0.2.5 shipped a bug: it picked the first id containing
    /// "llama" from the account list, which could be a Llama Guard text
    /// classifier - Groq then rejected every chat request. Selection is now
    /// deliberate and re-derived on every send, so a bad stored pick from an
    /// older build heals itself without the user re-entering the key.
    static let blockedModelPatterns = ["guard", "whisper", "tts", "embedding", "prompt-guard", "moderation"]
    static let preferredChatPatterns = ["llama-3.3-70b-versatile", "versatile", "instant", "gpt-oss", "instruct", "qwen", "kimi", "compound", "llama"]

    static func resolveChatModel(from ids: [String]? = nil) -> String {
        let list = ids ?? (UserDefaults.standard.stringArray(forKey: "mike.groqModels") ?? [])
        let candidates = list.filter { id in
            let low = id.lowercased()
            return !blockedModelPatterns.contains { low.contains($0) }
        }
        for pat in preferredChatPatterns {
            if let hit = candidates.first(where: { $0.lowercased().contains(pat) }) { return hit }
        }
        return candidates.first ?? "llama-3.3-70b-versatile"
    }

    /// Real check against Groq's model list. Returns a human-readable verdict.
    static func validate(key: String) async -> String {
        var req = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/models")!)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 20
        do {
            let session = URLSession(configuration: .ephemeral,
                                     delegate: SameHostOnlySession(originalHost: "api.groq.com"),
                                     delegateQueue: nil)
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return "No response from Groq." }
            if http.statusCode == 401 { return "Groq rejected that key. Check it and try again." }
            guard (200..<300).contains(http.statusCode),
                  let models = try? JSONDecoder().decode(ModelsResponse.self, from: data) else {
                return "Groq answered with status \(http.statusCode). The key is not verified."
            }
            let ids = models.data.map { $0.id }
            UserDefaults.standard.set(ids, forKey: "mike.groqModels")
            let model = resolveChatModel(from: ids)
            UserDefaults.standard.set(model, forKey: "mike.groqModel")
            // Listing models only proves the key reads the account. Actually
            // send one minimal chat request before claiming chat works.
            do {
                _ = try await chat(key: key, history: [Msg(role: "user", content: "Reply with: ok")], maxTokens: 4, model: model)
                return "Chat works with \(model) (\(ids.count) models on the account)."
            } catch {
                return "The key is valid, but a real chat request failed with \(model): \(error.localizedDescription)"
            }
        } catch {
            return "Couldn't reach Groq: \(error.localizedDescription)"
        }
    }

    static func chat(key: String, history: [Msg], maxTokens: Int = 1024, model: String? = nil) async throws -> String {
        let model = model ?? resolveChatModel()
        var req = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(ChatRequest(model: model, messages: history, max_tokens: maxTokens))
        let session = URLSession(configuration: .ephemeral,
                                 delegate: SameHostOnlySession(originalHost: "api.groq.com"),
                                 delegateQueue: nil)
        let (data, resp) = try await session.data(for: req)
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
