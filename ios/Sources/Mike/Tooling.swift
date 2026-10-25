import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Mike's real tool layer for the Groq provider: the model asks for a tool,
/// this code validates the request, runs read-only tools immediately, and
/// queues anything that changes something for the owner's approval first.
/// The loop is bounded - after maxRounds tool rounds it stops with an honest
/// error instead of spinning.
enum Tooling {
    static let maxRounds = 5

    // MARK: Wire types (OpenAI-compatible tool calling)

    struct ToolMsg: Codable {
        let role: String
        let content: String?
        let tool_calls: [ToolCall]?
        let tool_call_id: String?
        let name: String?
        init(role: String, content: String? = nil, tool_calls: [ToolCall]? = nil,
             tool_call_id: String? = nil, name: String? = nil) {
            self.role = role; self.content = content; self.tool_calls = tool_calls
            self.tool_call_id = tool_call_id; self.name = name
        }
    }

    struct ToolCall: Codable {
        let id: String
        let type: String?
        let function: Function
        struct Function: Codable { let name: String; let arguments: String }
    }

    struct ToolDef: Encodable {
        let type = "function"
        let function: F
        struct F: Encodable {
            let name: String
            let description: String
            let parameters: [String: ParamSchema]
        }
        struct ParamSchema: Encodable {
            let type: String
            let description: String?
            let properties: [String: P]?
            let required: [String]?
            struct P: Encodable { let type: String; let description: String }
        }
    }

    struct ChatWithToolsRequest: Encodable {
        let model: String
        let messages: [ToolMsg]
        let tools: [ToolDef]
        let max_tokens: Int
    }

    struct ToolChatResponse: Codable {
        let choices: [Choice]
        struct Choice: Codable { let message: ToolMsg }
    }

    static let tools: [ToolDef] = [
        ToolDef(function: .init(name: "get_current_time",
            description: "Get the current date and time on the owner's iPhone.",
            parameters: ["type": .init(type: "object", description: nil, properties: [:], required: [])])),
        ToolDef(function: .init(name: "remember",
            description: "Save a fact the owner asked you to remember. Needs the owner's approval before it is stored.",
            parameters: ["type": .init(type: "object", description: nil,
                properties: ["text": .init(type: "string", description: "The fact to remember, one short sentence.")], required: ["text"])])),
        ToolDef(function: .init(name: "recall",
            description: "Search things the owner asked you to remember.",
            parameters: ["type": .init(type: "object", description: nil,
                properties: ["query": .init(type: "string", description: "Word or phrase to look for.")], required: ["query"])])),
        ToolDef(function: .init(name: "schedule_reminder",
            description: "Schedule an on-device reminder notification for a future time. Needs the owner's approval before it is set.",
            parameters: ["type": .init(type: "object", description: nil,
                properties: [
                    "text": .init(type: "string", description: "What to remind about."),
                    "at": .init(type: "string", description: "When to fire, ISO 8601 with timezone, e.g. 2026-10-26T18:30:00+02:00."),
                ], required: ["text", "at"])])),
    ]

    // MARK: Argument validation (pure, testable)

    enum ToolError: Error, CustomStringConvertible {
        case unknownTool(String)
        case badArguments(String)
        var description: String {
            switch self {
            case .unknownTool(let n): return "Unknown tool: \(n)"
            case .badArguments(let why): return "Bad tool arguments: \(why)"
            }
        }
    }

    static func argsDict(_ call: ToolCall) throws -> [String: Any] {
        guard let data = call.function.arguments.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any] else {
            throw ToolError.badArguments("arguments are not a JSON object")
        }
        return dict
    }

    /// Read-only tools run immediately. Writes return nil - they must be
    /// queued for owner approval instead.
    static func isReadOnly(_ name: String) -> Bool {
        ["get_current_time", "recall"].contains(name)
    }

    static func validatedArgs(_ call: ToolCall) throws -> [String: Any] {
        let name = call.function.name
        guard ["get_current_time", "remember", "recall", "schedule_reminder"].contains(name) else {
            throw ToolError.unknownTool(name)
        }
        let args = try argsDict(call)
        switch name {
        case "remember":
            guard let t = args["text"] as? String, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, t.count <= 500 else {
                throw ToolError.badArguments("remember needs a non-empty text of at most 500 characters")
            }
        case "recall":
            guard let q = args["query"] as? String, !q.isEmpty, q.count <= 200 else {
                throw ToolError.badArguments("recall needs a non-empty query")
            }
        case "schedule_reminder":
            guard let t = args["text"] as? String, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, t.count <= 200 else {
                throw ToolError.badArguments("schedule_reminder needs reminder text of at most 200 characters")
            }
            guard let at = args["at"] as? String, let date = parseDate(at) else {
                throw ToolError.badArguments("schedule_reminder needs 'at' as ISO 8601, e.g. 2026-10-26T18:30:00+02:00")
            }
            let now = Date()
            guard date > now.addingTimeInterval(30) else {
                throw ToolError.badArguments("reminder time must be at least 30 seconds in the future")
            }
            guard date < now.addingTimeInterval(366 * 24 * 3600) else {
                throw ToolError.badArguments("reminder time must be within one year")
            }
        default: break
        }
        return args
    }

    static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    // MARK: Execution

    /// Runs a validated tool call. Read-only tools execute now; writes are
    /// queued in the Approvals tab and this returns a message the model must
    /// relay honestly.
    static func run(_ call: ToolCall, store: AgentStore) -> String {
        let name = call.function.name
        do {
            let args = try validatedArgs(call)
            if isReadOnly(name) {
                store.log("tool", "\(name) ran")
                switch name {
                case "get_current_time":
                    let f = DateFormatter()
                    f.dateStyle = .full; f.timeStyle = .long
                    return "Current device time: \(f.string(from: Date()))"
                case "recall":
                    let hits = store.recall(args["query"] as? String ?? "")
                    return hits.isEmpty
                        ? "Nothing remembered matches that."
                        : "Remembered:\n" + hits.prefix(10).map { "- \($0)" }.joined(separator: "\n")
                default:
                    return "Unhandled read-only tool."
                }
            }
            // Writes: queue for approval, do not execute.
            let title: String
            let detail: String
            if name == "remember" {
                title = "Remember something"
                detail = "\"\(args["text"] as? String ?? "")\" - stored on this phone only."
            } else {
                let at = args["at"] as? String ?? ""
                let dateText = parseDate(at).map { d -> String in
                    let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f.string(from: d)
                } ?? at
                title = "Set a reminder"
                detail = "\"\(args["text"] as? String ?? "")\" at \(dateText). Delivered by the iPhone as a local notification at the scheduled time (within a small system margin). No server involved."
            }
            let a = store.queueApproval(tool: name, title: title, detail: detail, argumentsJSON: call.function.arguments)
            return "This needs the owner's approval before I do it. It is queued in the Approvals tab (id \(a.id.prefix(8))). Tell the owner to approve or deny it there - do not say it is done."
        } catch {
            store.log("tool", "\(name) rejected: \(error.localizedDescription)")
            return "Tool request rejected: \(error.localizedDescription)"
        }
    }

    /// Executes an approved queued action. Called from the Approvals tab.
    static func executeApproved(_ approval: LocalApproval, store: AgentStore) {
        guard let data = approval.argumentsJSON.data(using: .utf8),
              let args = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            store.log("approval", "Couldn't run approved action - stored arguments unreadable.")
            return
        }
        switch approval.tool {
        case "remember":
            store.remember(args["text"] as? String ?? "")
            store.log("approval", "Approved and remembered: \"\(args["text"] as? String ?? "")\"")
        case "schedule_reminder":
            let text = args["text"] as? String ?? ""
            let at = args["at"] as? String ?? ""
            guard let date = parseDate(at) else {
                store.log("approval", "Approved reminder had an unreadable date; nothing scheduled.")
                return
            }
            scheduleNotification(text: text, at: date, store: store)
        default:
            store.log("approval", "Approved action for unknown tool \(approval.tool); nothing ran.")
        }
    }

    static func scheduleNotification(text: String, at date: Date, store: AgentStore) {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                guard granted else {
                    store.log("approval", "Notifications are off for Mike, so the reminder could not be set. Enable them in iPhone Settings > Mike.")
                    return
                }
                let content = UNMutableNotificationContent()
                content.title = "Mike reminder"
                content.body = text
                content.sound = .default
                let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
                center.add(req) { err in
                    DispatchQueue.main.async {
                        if let err = err {
                            store.log("approval", "Reminder failed to schedule: \(err.localizedDescription)")
                        } else {
                            store.log("approval", "Reminder set: \"\(text)\"")
                        }
                    }
                }
            }
        }
        #else
        store.log("approval", "Notifications unavailable on this platform; reminder not set.")
        #endif
    }
}
