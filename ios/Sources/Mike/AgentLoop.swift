import Foundation

/// The Groq agent loop: send the conversation with tool definitions, run any
/// requested tools through the approval-gated executor, feed results back,
/// repeat - at most Tooling.maxRounds rounds, then an honest stop.
enum AgentLoop {
    static let systemPrompt = """
    You are Mike, a personal assistant on the owner's iPhone. Be concise and honest.
    You have real tools: get_current_time, recall (search saved facts), remember \
    (save a fact - needs owner approval), schedule_reminder (local iPhone notification - needs owner approval).
    When a write tool answers that it is queued for approval, say exactly that and point \
    to the Approvals tab. Never claim you saved or scheduled something before the tool confirms it. \
    Never invent tool results. If you cannot do something, say so.
    """

    static func run(key: String, conversation: [Tooling.ToolMsg], store: AgentStore) async throws -> String {
        guard let model = GroqClient.resolveChatModel() else {
            throw NSError(domain: "Groq", code: 0, userInfo: [NSLocalizedDescriptionKey:
                "No supported chat model is available on this Groq account. Open Settings and re-test the key."])
        }
        var convo = [Tooling.ToolMsg(role: "system", content: systemPrompt)] + conversation
        for _ in 0..<Tooling.maxRounds {
            let msg = try await round(key: key, model: model, messages: convo)
            guard let calls = msg.tool_calls, !calls.isEmpty else {
                return msg.content ?? "(Groq returned an empty reply.)"
            }
            convo.append(msg)
            for call in calls {
                let result = Tooling.run(call, store: store)
                convo.append(Tooling.ToolMsg(role: "tool", content: result,
                                             tool_call_id: call.id, name: call.function.name))
            }
        }
        store.log("tool", "Stopped after \(Tooling.maxRounds) tool rounds - asked the model to wrap up.")
        return "I hit my step limit for one message (\(Tooling.maxRounds) tool rounds) and stopped rather than guessing. Ask me again and I'll pick it up."
    }

    private static func round(key: String, model: String, messages: [Tooling.ToolMsg]) async throws -> Tooling.ToolMsg {
        var req = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(Tooling.ChatWithToolsRequest(
            model: model, messages: messages, tools: Tooling.tools, max_tokens: 1024))
        let session = URLSession(configuration: .ephemeral,
                                 delegate: SameHostOnlySession(originalHost: "api.groq.com"),
                                 delegateQueue: nil)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            if let body = try? JSONDecoder().decode(GroqClient.ErrorBody.self, from: data) {
                throw NSError(domain: "Groq", code: http.statusCode,
                              userInfo: [NSLocalizedDescriptionKey: "Groq said: \(body.error.message)"])
            }
            throw NSError(domain: "Groq", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "Groq answered with status \(http.statusCode)."])
        }
        let out = try JSONDecoder().decode(Tooling.ToolChatResponse.self, from: data)
        guard let msg = out.choices.first?.message else {
            throw NSError(domain: "Groq", code: 0, userInfo: [NSLocalizedDescriptionKey: "Groq returned no message."])
        }
        return msg
    }
}
