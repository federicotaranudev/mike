import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: ProviderStore
    @State private var showSetup = false

    var body: some View {
        NavigationStack {
            List {
                Section("Where Mike thinks") {
                    HStack {
                        Text("Current")
                        Spacer()
                        Text(store.provider?.title ?? "Not set").foregroundStyle(.secondary)
                    }
                    Button("Change provider") { showSetup = true }
                    Text("Switching keeps your chats and memory. Mike never switches on its own.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if store.provider == .groq {
                    Section("Groq") {
                        Text(KeychainStore.load(KeychainStore.groqKey) != nil
                             ? "Key saved in the iPhone Keychain." : "No key saved yet.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("Remove Groq key", role: .destructive) {
                            KeychainStore.delete(KeychainStore.groqKey)
                        }
                    }
                }
                if store.provider == .backend {
                    Section("Backend") {
                        Text(UserDefaults.standard.string(forKey: "mike.baseURL") ?? "No URL set")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("Remove backend token", role: .destructive) {
                            KeychainStore.delete(KeychainStore.backendToken)
                        }
                    }
                }
                if store.provider == .local {
                    Section("On-device model") {
                        Text("Gemma 4 E2B. The on-device runtime is not in this build yet - chat says so until it lands. Nothing has been downloaded.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showSetup) {
                OnboardingView()
                    .environmentObject(store)
                    .environmentObject(APIClient())
            }
        }
    }
}

#Preview { SettingsView().environmentObject(ProviderStore()) }
