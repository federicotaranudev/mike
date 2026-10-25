import Foundation
import UserNotifications

/// Mike's proactive layer, v1: honest and bounded. When the app opens, Mike
/// checks real signals - actions waiting for your yes, reminders he scheduled
/// for you - and speaks first in chat when there is something worth saying.
///
/// Boundaries (by design, and the copy says so):
/// - At most one check-in per app launch, and only into an untouched chat.
/// - Mike does NOT run in the background. While the app is closed, the only
///   thing that can reach you is a reminder you (or an approved action)
///   scheduled - delivered by iOS as a normal notification.
/// - Mutations stay approval-gated; this layer only speaks, it never acts.
enum ProactiveEngine {
    private static var spokenThisLaunch = false
    private static let lastDigestKey = "mike.proactive.lastSignalDigest"

    /// Stable digest of everything a check-in could report. Pure so the
    /// selftest can verify dedup behavior without iOS notifications.
    static func signalDigest(approvalIDs: [String], reminderIDs: [String]) -> String {
        (approvalIDs.sorted().joined(separator: ",") + "|" + reminderIDs.sorted().joined(separator: ","))
    }

    /// Speak only when the signals changed since the last spoken check-in:
    /// relaunching the app with the same pending items stays silent (no spam),
    /// a new approval or reminder makes Mike speak again.
    static func shouldSpeak(currentDigest: String, defaults: UserDefaults = .standard) -> Bool {
        guard !currentDigest.isEmpty, currentDigest != "|" else { return false }
        return defaults.string(forKey: lastDigestKey) != currentDigest
    }

    static func markSpoken(_ digest: String, defaults: UserDefaults = .standard) {
        defaults.set(digest, forKey: lastDigestKey)
    }

    static func speakUpIfWarranted(store: AgentStore, deliver: @escaping (String) -> Void) {
        guard !spokenThisLaunch else { return }
        spokenThisLaunch = true
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { reqs in
            center.getDeliveredNotifications { notes in
                let waiting = store.approvals.filter { $0.status == .pending }
                // Signals are pending reminders AND reminders that fired while
                // Mike was closed - a delivered notification is exactly the
                // "while you were away" case this layer exists for.
                let pending = reqs.filter { $0.content.title == "Mike reminder" }
                let fired = notes.filter { $0.request.content.title == "Mike reminder" }
                let digest = signalDigest(approvalIDs: waiting.map { $0.id },
                                          reminderIDs: pending.map { $0.identifier } + fired.map { $0.request.identifier })
                guard (!waiting.isEmpty || !pending.isEmpty || !fired.isEmpty),
                      shouldSpeak(currentDigest: digest) else { return }
                var parts: [String] = []
                if !waiting.isEmpty {
                    var p = "\(waiting.count) thing\(waiting.count == 1 ? "" : "s") need\(waiting.count == 1 ? "s" : "") your yes in Approvals"
                    if let first = waiting.first { p += " (\"\(first.title)\")" }
                    parts.append(p)
                }
                if !pending.isEmpty {
                    let soonest = pending
                        .compactMap { ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() }
                        .sorted().first
                    var p = "\(pending.count) reminder\(pending.count == 1 ? "" : "s") set"
                    if let d = soonest {
                        let f = DateFormatter()
                        f.dateFormat = "HH:mm"
                        p += ", next at \(f.string(from: d))"
                    }
                    parts.append(p)
                }
                if !fired.isEmpty {
                    var p = "\(fired.count) reminder\(fired.count == 1 ? "" : "s") fired while Mike was closed"
                    if let first = fired.first {
                        let body = first.request.content.body
                        if !body.isEmpty { p += " (\"\(body)\")" }
                    }
                    parts.append(p)
                }
                let text = "Welcome back - while you were away: " + parts.joined(separator: "; ") + "."
                DispatchQueue.main.async {
                    markSpoken(digest)
                    store.log("proactive", "Spoke up first: \(text)")
                    deliver(text)
                }
            }
        }
    
    }
}
