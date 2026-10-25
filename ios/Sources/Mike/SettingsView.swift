import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: ProviderStore
    @EnvironmentObject var models: ModelManager
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
                    Text("Switching keeps your chats and settings. Mike never switches on its own.")
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
                        switch models.state {
                        case .notDownloaded:
                            Text("Gemma 4 E2B (Q4_0, 2.8 GB). Downloads from Hugging Face over HTTPS - no account needed. Keep Mike open while it downloads.")
                                .font(.footnote).foregroundStyle(.secondary)
                            Button("Download model") { models.startDownload() }
                        case .downloading(let p):
                            ProgressView(value: p) { Text("Downloading model - \(Int(p * 100))%") }
                            Button("Cancel", role: .destructive) { models.cancelDownload() }
                        case .downloaded(let bytes):
                            Text("Gemma 4 E2B is on this phone (\(String(format: "%.1f", Double(bytes) / 1e9)) GB). The runtime that runs it (llama.cpp) is not in this build yet - chat will say so until it lands, not fake replies.")
                                .font(.footnote).foregroundStyle(.secondary)
                            Button("Delete model", role: .destructive) { models.deleteModel() }
                        case .failed(let why):
                            Text(why).font(.footnote).foregroundStyle(.secondary)
                            Button("Try again") { models.startDownload() }
                        }
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

#Preview { SettingsView().environmentObject(ProviderStore()).environmentObject(ModelManager()) }
