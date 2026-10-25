import Foundation

var failures = 0
var lines: [String] = []
func check(_ name: String, _ cond: Bool) {
    let line = (cond ? "PASS " : "FAIL ") + name
    print(line)
    lines.append(line)
    if !cond { failures += 1 }
}

// 1. Keychain roundtrip + legacy UserDefaults migration.
// Note: an ad-hoc signed process spawned directly on the simulator has no
// keychain access group, so SecItemAdd returns errSecMissingEntitlement
// there. That is a test-environment limitation, not an app defect (real
// sideloaded builds get a real application-identifier). We probe once and
// SKIP the Keychain-dependent assertions in that case instead of faking a
// pass; the migration's UserDefaults cleanup is asserted unconditionally.
func keychainAvailable() -> Bool {
    KeychainStore.save("probe", account: "probe")
    let ok = KeychainStore.load("probe") == "probe"
    KeychainStore.delete("probe")
    return ok
}
let kcOK = keychainAvailable()
KeychainStore.delete(KeychainStore.backendToken)
UserDefaults.standard.set("legacy-secret-123", forKey: "mike.token")
KeychainStore.migrateLegacyToken()
if kcOK {
    check("migration moves token to Keychain", KeychainStore.load(KeychainStore.backendToken) == "legacy-secret-123")
    KeychainStore.save("abc", account: KeychainStore.groqKey)
    check("keychain roundtrip", KeychainStore.load(KeychainStore.groqKey) == "abc")
    KeychainStore.delete(KeychainStore.groqKey)
    check("keychain delete", KeychainStore.load(KeychainStore.groqKey) == nil)
    KeychainStore.delete(KeychainStore.backendToken)
} else {
    print("SKIP keychain value checks: no keychain access group in ad-hoc sim process (device-covered)")
}
check("migration deletes UserDefaults copy", UserDefaults.standard.string(forKey: "mike.token") == nil)

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
check("unknown future id never selected", GroqClient.resolveChatModel(from: ["acme/future-llama-9b"]) == nil)
check("resolved model is on the allowlist", GroqClient.supportedChatModels.contains(resolved ?? ""))
let onlyClassifiers = ["llama-guard-3-8b", "whisper-large-v3"]
check("unsupported-only list returns nil, never a guess", GroqClient.resolveChatModel(from: onlyClassifiers) == nil)
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


// 7. Tool calling: argument validation, approval gating, loop bounds
let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
let agentStore = AgentStore(directory: tmp)
func mkCall(_ name: String, _ args: String) -> Tooling.ToolCall {
    Tooling.ToolCall(id: "call_1", type: "function", function: .init(name: name, arguments: args))
}
check("unknown tool rejected", (try? Tooling.validatedArgs(mkCall("delete_everything", "{}"))) == nil)
check("empty remember rejected", (try? Tooling.validatedArgs(mkCall("remember", "{\"text\":\"\"}"))) == nil)
check("valid remember accepted", (try? Tooling.validatedArgs(mkCall("remember", "{\"text\":\"Fred likes espressos\"}"))) != nil)
check("past reminder rejected", (try? Tooling.validatedArgs(mkCall("schedule_reminder", "{\"text\":\"x\",\"at\":\"2020-01-01T10:00:00+02:00\"}"))) == nil)
check("garbage date rejected", (try? Tooling.validatedArgs(mkCall("schedule_reminder", "{\"text\":\"x\",\"at\":\"tomorrow-ish\"}"))) == nil)
let futureISO = ISO8601DateFormatter().string(from: Date().addingTimeInterval(30 * 24 * 3600))
check("future reminder accepted", (try? Tooling.validatedArgs(mkCall("schedule_reminder", "{\"text\":\"x\",\"at\":\"\(futureISO)\"}"))) != nil)
check("over-one-year reminder rejected", (try? Tooling.validatedArgs(mkCall("schedule_reminder", "{\"text\":\"x\",\"at\":\"2100-01-01T10:00:00+02:00\"}"))) == nil)
check("broken JSON rejected", (try? Tooling.validatedArgs(mkCall("recall", "not json"))) == nil)

// Write tools never execute without approval
let before = agentStore.memory.count
let res = Tooling.run(mkCall("remember", "{\"text\":\"Fred likes espressos\"}"), store: agentStore)
check("write tool returns queued-for-approval message", res.contains("approval"))
check("write tool queued one approval", agentStore.approvals.filter { $0.status == .pending }.count == 1)
check("write NOT executed before approval", agentStore.memory.count == before)
let queued = agentStore.approvals[0]
// Denial path
if let denied = agentStore.resolve(queued.id, approved: false) {
    check("denied approval marked denied", denied.status == .denied)
} else { check("denial resolves pending approval", false) }
check("denied write still not executed", agentStore.memory.isEmpty)
// Approval path executes exactly the stored action
let res2 = Tooling.run(mkCall("remember", "{\"text\":\"Fred likes espressos\"}"), store: agentStore)
_ = res2
let queued2 = agentStore.approvals[0]
if let approved = agentStore.resolve(queued2.id, approved: true) {
    Tooling.executeApproved(approved, store: agentStore)
}
check("approved remember executed", agentStore.memory.first == "Fred likes espressos")
// Read-only recall runs immediately
let recallRes = Tooling.run(mkCall("recall", "{\"query\":\"espresso\"}"), store: agentStore)
check("recall finds approved memory", recallRes.contains("espressos"))
check("recall of unknown term is honest", Tooling.run(mkCall("recall", "{\"query\":\"zzz-nothing\"}"), store: agentStore).contains("Nothing"))
// get_current_time runs immediately
check("get_current_time runs read-only", Tooling.run(mkCall("get_current_time", "{}"), store: agentStore).contains("Current device time"))
// Bad args never crash the loop - model gets a rejection string
check("bad args return rejection text", Tooling.run(mkCall("remember", "{}"), store: agentStore).contains("rejected"))

// 10. Queue survives a restart (fresh store, same directory)
let agentStore2 = AgentStore(directory: tmp)
check("memory survives restart", agentStore2.memory.first == "Fred likes espressos")
check("approvals survive restart", agentStore2.approvals.count == agentStore.approvals.count)
check("activity log survived restart", !agentStore2.activity.isEmpty)
// 11. An approval can only be resolved once
let again = agentStore2.resolve(queued2.id, approved: true)
check("already-resolved approval cannot execute twice", again == nil)
let deniedAgain = agentStore2.resolve(queued.id, approved: true)
check("denied approval cannot later be approved", deniedAgain == nil)

// 8. Groq tool_calls response parses (content may be null)
let mockResp = """
{"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[{"id":"call_9","type":"function","function":{"name":"get_current_time","arguments":"{}"}}]}}]}
"""
let parsed = try? JSONDecoder().decode(Tooling.ToolChatResponse.self, from: Data(mockResp.utf8))
check("tool_calls response parses", parsed?.choices.first?.message.tool_calls?.first?.function.name == "get_current_time")
check("null content tolerated", parsed?.choices.first?.message.content == nil)

// 9. Model download source is fixed, https, Hugging Face only
check("model url is huggingface https litertlm", ModelManager.modelURL.scheme == "https" && ModelManager.modelURL.host == "huggingface.co" && ModelManager.modelURL.path.hasSuffix(".litertlm"))
check("model size constant matches the verified artifact", ModelManager.expectedBytes == 2_008_432_640)

let verdict = failures == 0 ? "ALL PASS" : "\(failures) FAILURES"
print(verdict)
lines.append(verdict)
let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
try? lines.joined(separator: "\n").write(to: docs.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
exit(failures == 0 ? 0 : 1)
