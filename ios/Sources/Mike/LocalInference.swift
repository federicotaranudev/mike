import Foundation

#if canImport(LiteRTLM)
import LiteRTLM

/// Real on-device inference via LiteRT-LM on the iPhone GPU (Metal). The
/// engine stays alive between messages so the ~2 GB model is loaded once,
/// not on every send. Model file comes from ModelManager's download.
final class LocalEngine {
    static let shared = LocalEngine()
    private var engine: Engine?
    private var conversation: Conversation?

    func reply(to text: String, modelPath: String) async throws -> String {
        if engine == nil {
            let config = EngineConfig(modelPath: modelPath, backend: .gpu,
                                      cacheDir: NSTemporaryDirectory())
            let e = try Engine(engineConfig: config)
            // Engine is an actor; heavy model load happens inside initialize().
            try await e.initialize()
            let c = try await e.createConversation()
            engine = e
            conversation = c
        }
        guard let conversation else {
            throw NSError(domain: "Mike", code: 0, userInfo: [NSLocalizedDescriptionKey: "Local engine failed to start."])
        }
        let response = try await conversation.sendMessage(Message(text))
        return response.toString
    }
}
#endif

enum LocalInference {
    /// True only in builds that actually ship the LiteRT-LM runtime.
    static var runtimeBundled: Bool {
        #if canImport(LiteRTLM)
        return true
        #else
        return false
        #endif
    }

    static func reply(to text: String, modelPath: String) async throws -> String {
        #if canImport(LiteRTLM)
        return try await LocalEngine.shared.reply(to: text, modelPath: modelPath)
        #else
        throw NSError(domain: "Mike", code: 0, userInfo: [NSLocalizedDescriptionKey:
            "The on-device runtime is not in this build."])
        #endif
    }
}
