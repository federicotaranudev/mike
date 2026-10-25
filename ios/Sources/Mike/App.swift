import SwiftUI

@main
struct MikeApp: App {
    @StateObject private var api = APIClient()
    // Initial tab. The sim-screenshots workflow compiles variants with
    // -D SIM_TAB_APPROVALS / -D SIM_TAB_ACTIVITY to capture each tab.
    // Device builds define neither, so Mike always opens on Chat.
    #if SIM_TAB_APPROVALS
    @State private var tab = 1
    #elseif SIM_TAB_ACTIVITY
    @State private var tab = 2
    #else
    @State private var tab = 0
    #endif

    var body: some Scene {
        WindowGroup {
            TabView(selection: $tab) {
                ChatView()
                    .tag(0)
                    .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
                ApprovalsView()
                    .tag(1)
                    .tabItem { Label("Approvals", systemImage: "checkmark.shield") }
                ActivityView()
                    .tag(2)
                    .tabItem { Label("Activity", systemImage: "list.bullet.rectangle") }
            }
            .environmentObject(api)
            .preferredColorScheme(.dark)
        }
    }
}
