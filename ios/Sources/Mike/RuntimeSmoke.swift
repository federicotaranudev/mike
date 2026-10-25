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
            // Simulator permission dialogs are not grantable via simctl/TCC -
            // the system dialog is the only path, and it races the UI driver's
            // attach. So retry: check pending first (never double-schedule),
            // and attempt again every 7s until one sticks (max 4 attempts).
            let store = AgentStore()
            let center = UNUserNotificationCenter.current()
            var attempt = 0
            func trySchedule() {
                attempt += 1
                center.getPendingNotificationRequests { reqs in
                    let mine = reqs.filter { $0.content.title == "Mike reminder" }
                    if !mine.isEmpty {
                        NSLog("NOTIF_PENDING count=\(reqs.count)")
                        for r in reqs { NSLog("NOTIF_PENDING_ITEM \(r.content.body)") }
                        return
                    }
                    NSLog("NOTIF_SCHEDULING attempt=\(attempt) via Tooling.scheduleNotification")
                    Tooling.scheduleNotification(text: "Mike CI notification smoke",
                                                 at: Date().addingTimeInterval(65), store: store)
                    center.getNotificationSettings { st in
                        // 0 notDetermined, 1 denied, 2 authorized, 3 provisional, 4 ephemeral
                        NSLog("NOTIF_AUTH_STATUS raw=\(st.authorizationStatus.rawValue)")
                    }
                    if attempt < 4 {
                        DispatchQueue.global().asyncAfter(deadline: .now() + 7) { trySchedule() }
                    } else {
                        DispatchQueue.global().asyncAfter(deadline: .now() + 7) {
                            center.getNotificationSettings { st in
                                NSLog("NOTIF_AUTH_STATUS_AT_CHECK raw=\(st.authorizationStatus.rawValue)")
                            }
                            center.getPendingNotificationRequests { r2 in
                                NSLog("NOTIF_PENDING count=\(r2.count)")
                                for r in r2 { NSLog("NOTIF_PENDING_ITEM \(r.content.body)") }
                            }
                        }
                    }
                }
            }
            trySchedule()
            return
        }

        if args.contains("-NotifCheck") {
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                UNUserNotificationCenter.current().getDeliveredNotifications { notes in
                    NSLog("NOTIF_DELIVERED count=\(notes.count)")
                    print("NOTIF_DELIVERED count=\(notes.count)")
                    for n in notes {
                        NSLog("NOTIF_DELIVERED_ITEM \(n.request.content.body)")
                        print("NOTIF_DELIVERED_ITEM \(n.request.content.body)")
                    }
                    exit(notes.isEmpty ? 1 : 0)
                }
            }
            return
        }

        guard let i = args.firstIndex(of: "-RuntimeSmoke"), args.count > i + 1 else { return }
        let path = args[i + 1]
        let forceCPU = args.contains("cpu")
        NSLog("SMOKE_START path=\(path) backend=\(forceCPU ? "cpu" : "gpu") bundled=\(LocalInference.runtimeBundled)")
        print("SMOKE_START path=\(path) backend=\(forceCPU ? "cpu" : "gpu") bundled=\(LocalInference.runtimeBundled)")
        fflush(stdout)
        DispatchQueue.global().asyncAfter(deadline: .now() + 600) {
            NSLog("SMOKE_RESULT TIMEOUT after 600s")
            print("SMOKE_RESULT TIMEOUT after 600s")
            fflush(stdout)
            exit(2)
        }
        Task {
            do {
                let out = try await LocalInference.smokeReply(
                    prompt: "Reply with the single word OK.", modelPath: path, forceCPU: forceCPU)
                NSLog("SMOKE_RESULT OK \(out)")
                print("SMOKE_RESULT OK \(out)")
                fflush(stdout)
                exit(0)
            } catch {
                NSLog("SMOKE_RESULT FAIL \(error)")
                print("SMOKE_RESULT FAIL \(error)")
                fflush(stdout)
                exit(1)
            }
        }
    }
}
