import Foundation

var failures = 0
var lines: [String] = []
func check(_ name: String, _ cond: Bool) {
    let line = (cond ? "PASS " : "FAIL ") + name
    print(line)
    lines.append(line)
    if !cond { failures += 1 }
}

// 1. Keychain roundtrip + legacy UserDefaults migration
KeychainStore.delete(KeychainStore.backendToken)
UserDefaults.standard.set("legacy-secret-123", forKey: "mike.token")
KeychainStore.migrateLegacyToken()
check("migration moves token to Keychain", KeychainStore.load(KeychainStore.backendToken) == "legacy-secret-123")
check("migration deletes UserDefaults copy", UserDefaults.standard.string(forKey: "mike.token") == nil)
KeychainStore.save("abc", account: KeychainStore.groqKey)
check("keychain roundtrip", KeychainStore.load(KeychainStore.groqKey) == "abc")
KeychainStore.delete(KeychainStore.groqKey)
check("keychain delete", KeychainStore.load(KeychainStore.groqKey) == nil)
KeychainStore.delete(KeychainStore.backendToken)

// 2. Redirect policy fail-closed
func req(_ s: String) -> URLRequest { URLRequest(url: URL(string: s)!) }
check("cross-host redirect blocked", !RedirectPolicy.allowed(newRequest: req("https://evil.example.com/x"), originalHost: "api.groq.com"))
check("plain-http redirect blocked", !RedirectPolicy.allowed(newRequest: req("http://api.groq.com/x"), originalHost: "api.groq.com"))
check("same-host https redirect allowed", RedirectPolicy.allowed(newRequest: req("https://api.groq.com/v1"), originalHost: "api.groq.com"))

// 3. APIClient refuses plain HTTP before any network call
let api = APIClient()
api.baseURL = URL(string: "http://192.168.1.5:8787")
let sem = DispatchSemaphore(value: 0)
var threw = false
Task {
    do { _ = try await api.status(); } catch { threw = true }
    sem.signal()
}
_ = sem.wait(timeout: .now() + 5)
check("APIClient refuses plain http", threw)

// 5. Groq chat-model selection: classifiers/guards/audio never picked,
// even when they sort first in the account's model list (the v0.2.5 bug).
let mockList = [
    "llama-guard-3-8b", "llama-prompt-guard-2-86m", "whisper-large-v3",
    "llama-3.1-8b-instant", "llama-3.3-70b-versatile", "openai/gpt-oss-120b",
    "qwen/qwen3-32b", "mixtral-8x7b-32768", "gemma2-9b-it",
    "deepseek-r1-distill-llama-70b", "llama-3.2-3b-preview"
]
let resolved = GroqClient.resolveChatModel(from: mockList)
check("classifier never selected from 11-model list", resolved == "llama-3.3-70b-versatile")
check("resolved model is not blocked", !GroqClient.blockedModelPatterns.contains { resolved.lowercased().contains($0) })
let onlyClassifiers = ["llama-guard-3-8b", "whisper-large-v3"]
check("all-blocked list falls back to chat default", GroqClient.resolveChatModel(from: onlyClassifiers) == "llama-3.3-70b-versatile")
// 6. A bad stored pick from an older build is ignored on the next send
UserDefaults.standard.set("llama-guard-3-8b", forKey: "mike.groqModel")
UserDefaults.standard.set(mockList, forKey: "mike.groqModels")
check("stale bad model self-heals from stored list", GroqClient.resolveChatModel() == "llama-3.3-70b-versatile")
UserDefaults.standard.removeObject(forKey: "mike.groqModel")
UserDefaults.standard.removeObject(forKey: "mike.groqModels")

// 4. Provider choice persists and reloads
UserDefaults.standard.removeObject(forKey: "mike.provider")
check("fresh store has no provider", ProviderStore().provider == nil)
let store = ProviderStore()
store.select(.groq)
check("provider persisted", UserDefaults.standard.string(forKey: "mike.provider") == "groq")
check("reloaded provider", ProviderStore().provider == .groq)
UserDefaults.standard.removeObject(forKey: "mike.provider")

let verdict = failures == 0 ? "ALL PASS" : "\(failures) FAILURES"
print(verdict)
lines.append(verdict)
let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
try? lines.joined(separator: "\n").write(to: docs.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
exit(failures == 0 ? 0 : 1)
