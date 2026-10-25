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
                            Picker("Model build", selection: Binding(
                                get: { models.artifact },
                                set: { models.select($0) })) {
                                ForEach(ModelManager.Artifact.allCases) { a in
                                    Text(a.pickTitle).tag(a)
                                }
                            }
                            Text(models.artifact.pickBlurb)
                                .font(.footnote).foregroundStyle(.secondary)
                            if LocalInference.runtimeBundled {
                                Text("Gemma 4 E2B in LiteRT-LM format. Downloads from Hugging Face over HTTPS - no account needed, and the file is checked against the publisher's checksum after downloading. Keep Mike open while it downloads. Only download if that is OK.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            } else {
                                Text("Gemma 4 E2B in LiteRT-LM format - but this build does not include the runtime, so the file cannot chat yet. Downloads from Hugging Face over HTTPS - no account needed. Only download if that is OK.")
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
                                Text("Gemma 4 E2B (\(models.artifact.pickTitle)) is on this phone (\(String(format: "%.1f", Double(bytes) / 1e9)) GB), checksum verified. The first reply loads the model (slow on first use), and iPhone 13 behavior is untested. If a local reply fails you get the real error, never a fake one.")
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
