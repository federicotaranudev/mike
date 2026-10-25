import Foundation
import UserNotifications

/// CI-only validation entry points, activated by exact launch arguments:
///   -RuntimeSmoke <modelPath> [cpu]  - real engine init + one generation
///   -NotifSmoke                      - schedule a real reminder via the same
///                                      Tooling.scheduleNotification code an
///                                      approved reminder uses, then exit
///   -NotifCheck                      - report delivered notifications, then exit
/// Device builds ship this too but it only activates on those exact arguments;
/// normal launches skip it immediately. Not a user feature.
enum RuntimeSmoke {
    static func runIfRequested() {
        let args = ProcessInfo.processInfo.arguments

        if args.contains("-NotifSmoke") {
            print("NOTIF_SCHEDULING via Tooling.scheduleNotification")
            let store = AgentStore()
            let date = Date().addingTimeInterval(65)
            Tooling.scheduleNotification(text: "Mike CI notification smoke", at: date, store: store)
            // Auth + add callbacks are async; report pending requests, then exit.
            DispatchQueue.global().asyncAfter(deadline: .now() + 8) {
                UNUserNotificationCenter.current().getPendingNotificationRequests { reqs in
                    print("NOTIF_PENDING count=\(reqs.count)")
                    for r in reqs { print("NOTIF_PENDING_ITEM \(r.content.body)") }
                    exit(reqs.isEmpty ? 1 : 0)
                }
            }
            return
        }

        if args.contains("-NotifCheck") {
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                UNUserNotificationCenter.current().getDeliveredNotifications { notes in
                    print("NOTIF_DELIVERED count=\(notes.count)")
                    for n in notes { print("NOTIF_DELIVERED_ITEM \(n.request.content.body)") }
                    exit(notes.isEmpty ? 1 : 0)
                }
            }
            return
        }

        guard let i = args.firstIndex(of: "-RuntimeSmoke"), args.count > i + 1 else { return }
        let path = args[i + 1]
        let forceCPU = args.contains("cpu")
        print("SMOKE_START path=\(path) backend=\(forceCPU ? "cpu" : "gpu") bundled=\(LocalInference.runtimeBundled)")
        DispatchQueue.global().asyncAfter(deadline: .now() + 600) {
            print("SMOKE_RESULT TIMEOUT after 600s")
            exit(2)
        }
        Task {
            do {
                let out = try await LocalInference.smokeReply(
                    prompt: "Reply with the single word OK.", modelPath: path, forceCPU: forceCPU)
                print("SMOKE_RESULT OK \(out)")
                exit(0)
            } catch {
                print("SMOKE_RESULT FAIL \(error)")
                exit(1)
            }
        }
    }
}
