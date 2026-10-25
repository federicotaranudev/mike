import Foundation

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: Role
    let text: String
    let time: Date

    enum Role: String, Codable { case user, mike }

    init(id: UUID = UUID(), role: Role, text: String, time: Date = Date()) {
        self.id = id; self.role = role; self.text = text; self.time = time
    }
}

struct Approval: Identifiable, Codable {
    let id: String
    let summary: String
    let detail: String
    let createdAt: Date
    var status: Status

    enum Status: String, Codable { case pending, approved, denied }
}

struct ActivityEntry: Identifiable, Codable {
    let id: String
    let kind: String
    let summary: String
    let time: Date
}

struct CoreStatus: Codable {
    let providerConfigured: Bool
    let quotaRemainingToday: Int?
    let paused: Bool
}
