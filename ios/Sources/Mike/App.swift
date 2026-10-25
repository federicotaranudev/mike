import SwiftUI

@main
struct MikeApp: App {
    @StateObject private var api = APIClient()
    @StateObject private var providers = ProviderStore()
    @StateObject private var agent = AgentStore()
    @StateObject private var models = ModelManager()
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
                    VStack(spacing: 0) {
                        ZStack {
                            switch tab {
                            case 1: ApprovalsView()
                            case 2: ActivityView()
                            case 3: SettingsView()
                            default: ChatView()
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        navBar
                    }
                } else {
                    OnboardingView()
                }
                #endif
            }
            .environmentObject(api)
            .environmentObject(providers)
            .environmentObject(agent)
            .environmentObject(models)
            .preferredColorScheme(.dark)
        }
    }

    /// Floating glass capsule nav, icons only (reference: Instagram-style bar
    /// the user sent). Only real tabs, each with an accessibility label.
    private var navBar: some View {
        HStack(spacing: 4) {
            navButton(0, "bubble.left.and.bubble.right", "Chat")
            navButton(1, "checkmark.shield", "Approvals")
            navButton(2, "list.bullet.rectangle", "Activity")
            navButton(3, "gearshape", "Settings")
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
    }

    private func navButton(_ index: Int, _ icon: String, _ label: String) -> some View {
        Button { tab = index } label: {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(tab == index ? Color.gray.opacity(0.55) : Color.clear)
                .clipShape(Capsule())
                .accessibilityLabel(label)
        }
        .buttonStyle(.plain)
    }
}
