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
                            if LocalInference.runtimeBundled {
                                Text("Gemma 4 E2B (2.0 GB, LiteRT-LM format, runs on the iPhone GPU). Downloads from Hugging Face over HTTPS - no account needed, and the file is checked against the publisher's checksum after downloading. Keep Mike open while it downloads. Heads up: the first reply loads the model, which takes a while, and 2 GB on an iPhone 13 (4 GB RAM) is untested - it may be tight. Only download if that is OK.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            } else {
                                Text("Gemma 4 E2B (2.0 GB, LiteRT-LM format, made for the iPhone GPU - but this build does not include the runtime, so the file cannot chat yet). Downloads from Hugging Face over HTTPS - no account needed. Only download if that is OK.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Button("Download model") { models.startDownload() }
                        case .downloading(let p):
                            ProgressView(value: p) { Text("Downloading model - \(Int(p * 100))%") }
                            Button("Cancel", role: .destructive) { models.cancelDownload() }
                        case .verifying:
                            ProgressView { Text("Checking the file against the publisher's checksum...") }
                        case .downloaded(let bytes):
                            if LocalInference.runtimeBundled {
                                Text("Gemma 4 E2B is on this phone (\(String(format: "%.1f", Double(bytes) / 1e9)) GB), checksum verified. Local chat runs it on the GPU - the first reply loads the model (slow on first use), and iPhone 13 memory is untested. If a local reply fails you get the real error, never a fake one.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            } else {
                                Text("Gemma 4 E2B is on this phone (\(String(format: "%.1f", Double(bytes) / 1e9)) GB), checksum verified. This build does not include the runtime, so the file cannot chat yet.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
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
