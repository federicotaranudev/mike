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
            let config = try EngineConfig(modelPath: modelPath, backend: .gpu,
                                          cacheDir: NSTemporaryDirectory())
            let e = Engine(engineConfig: config)
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
        return try response.toString
    }
}
#endif

enum LocalInference {
    /// True only in builds that actually ship the LiteRT-LM runtime.
    static var runtimeBundled: Bool {
        // SIM_RUNTIME_BUNDLED is set only by the sim-screenshots CI variant that
        // renders the exact copy a runtime-bundled (device) build shows.
        #if SIM_RUNTIME_BUNDLED
        return true
        #elseif canImport(LiteRTLM)
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

    /// One-shot engine init + single generation for CI validation (RuntimeSmoke).
    /// Separate from LocalEngine so a smoke run never reuses app state.
    static func smokeReply(prompt: String, modelPath: String, forceCPU: Bool) async throws -> String {
        #if canImport(LiteRTLM)
        let backend: Backend = forceCPU ? .cpu() : .gpu
        let config = try EngineConfig(modelPath: modelPath, backend: backend,
                                      cacheDir: NSTemporaryDirectory())
        let e = Engine(engineConfig: config)
        let t0 = Date()
        try await e.initialize()
        let initSecs = Date().timeIntervalSince(t0)
        let c = try await e.createConversation()
        let t1 = Date()
        let r = try await c.sendMessage(Message(prompt))
        let genSecs = Date().timeIntervalSince(t1)
        return "init=\(String(format: "%.1f", initSecs))s gen=\(String(format: "%.1f", genSecs))s reply=\(try r.toString)"
        #else
        throw NSError(domain: "Mike", code: 0, userInfo: [NSLocalizedDescriptionKey:
            "runtime not bundled in this build"])
        #endif
    }
}
