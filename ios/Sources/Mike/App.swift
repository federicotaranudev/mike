import SwiftUI

@main
struct MikeApp: App {
    @StateObject private var api = APIClient()
    @StateObject private var providers = ProviderStore()
    // The sim-screenshots workflow compiles variants:
    // -D SIM_TAB_APPROVALS / SIM_TAB_ACTIVITY / SIM_TAB_SETTINGS: open that tab
    // -D SIM_ONBOARDING: force the first-launch setup screen
    // -D SIM_FORCE_LOCAL: pretend "On this iPhone" was picked, so the chat shows
    //   the honest "runtime not in this build" state.
    // Device builds define none of these.
    #if SIM_TAB_APPROVALS
    @State private var tab = 1
    #elseif SIM_TAB_ACTIVITY
    @State private var tab = 2
    #elseif SIM_TAB_SETTINGS
    @State private var tab = 3
    #else
    @State private var tab = 0
    #endif

    var body: some Scene {
        WindowGroup {
            Group {
                #if SIM_ONBOARDING
                OnboardingView()
                #else
                if providers.hasCompletedSetup {
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
                        SettingsView()
                            .tag(3)
                            .tabItem { Label("Settings", systemImage: "gearshape") }
                    }
                } else {
                    OnboardingView()
                }
                #endif
            }
            .environmentObject(api)
            .environmentObject(providers)
            .preferredColorScheme(.dark)
        }
    }
}
