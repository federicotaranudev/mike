import Foundation
import Combine

/// Local, on-device record of what Mike wants to do (approvals) and what Mike
/// did (activity). Lives in Documents as JSON - nothing leaves the phone.
/// The Approvals and Activity tabs read from here when no backend core is
/// configured, instead of showing a fake "can't reach the core" error.
final class AgentStore: ObservableObject {
    @Published private(set) var approvals: [LocalApproval] = []
    @Published private(set) var activity: [ActivityEntry] = []
    @Published private(set) var memory: [String] = []

    private let approvalsURL: URL
    private let activityURL: URL
    private let memoryURL: URL

    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        approvalsURL = dir.appendingPathComponent("mike-approvals.json")
        activityURL = dir.appendingPathComponent("mike-activity.json")
        memoryURL = dir.appendingPathComponent("mike-memory.json")
        approvals = (try? JSONDecoder().decode([LocalApproval].self, from: Data(contentsOf: approvalsURL))) ?? []
        activity = (try? JSONDecoder().decode([ActivityEntry].self, from: Data(contentsOf: activityURL))) ?? []
        memory = (try? JSONDecoder().decode([String].self, from: Data(contentsOf: memoryURL))) ?? []
    }

    private func persist() {
        try? JSONEncoder().encode(approvals).write(to: approvalsURL, options: .atomic)
        try? JSONEncoder().encode(Array(activity.suffix(200))).write(to: activityURL, options: .atomic)
        try? JSONEncoder().encode(Array(memory.suffix(200))).write(to: memoryURL, options: .atomic)
    }

    func log(_ kind: String, _ summary: String) {
        activity.insert(ActivityEntry(id: UUID().uuidString, kind: kind, summary: summary, time: Date()), at: 0)
        persist()
    }

    @discardableResult
    func queueApproval(tool: String, title: String, detail: String, argumentsJSON: String) -> LocalApproval {
        let a = LocalApproval(id: UUID().uuidString, title: title, detail: detail,
                              tool: tool, argumentsJSON: argumentsJSON,
                              createdAt: Date(), status: .pending)
        approvals.insert(a, at: 0)
        log("approval", "Queued for approval: \(title)")
        persist()
        return a
    }

    func resolve(_ id: String, approved: Bool) -> LocalApproval? {
        guard let i = approvals.firstIndex(where: { $0.id == id && $0.status == .pending }) else { return nil }
        approvals[i].status = approved ? .approved : .denied
        persist()
        return approvals[i]
    }

    func remember(_ text: String) {
        memory.insert(text, at: 0)
        persist()
    }

    func recall(_ query: String) -> [String] {
        let q = query.lowercased()
        return memory.filter { $0.lowercased().contains(q) }
    }
}

struct LocalApproval: Identifiable, Codable {
    let id: String
    let title: String
    let detail: String
    let tool: String
    let argumentsJSON: String
    let createdAt: Date
    var status: Approval.Status
}
