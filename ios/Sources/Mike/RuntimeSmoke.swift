import Foundation

/// CI-only runtime validation: `simctl launch --console booted <bundle> -RuntimeSmoke <modelPath> [cpu]`
/// Runs a REAL engine init + one generation on the simulator and prints a
/// machine-readable SMOKE_RESULT line, then exits. Device builds ship this too
/// but it only activates on that exact launch argument; normal launches skip
/// it immediately. Not a user feature.
enum RuntimeSmoke {
    static func runIfRequested() {
        let args = ProcessInfo.processInfo.arguments
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
