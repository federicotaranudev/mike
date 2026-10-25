import SwiftUI

@main
struct MikeApp: App {
    @StateObject private var api = APIClient()

    var body: some Scene {
        WindowGroup {
            TabView {
                ChatView()
                    .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
                ApprovalsView()
                    .tabItem { Label("Approvals", systemImage: "checkmark.shield") }
                ActivityView()
                    .tabItem { Label("Activity", systemImage: "list.bullet.rectangle") }
            }
            .environmentObject(api)
            .preferredColorScheme(.dark)
        }
    }
}
