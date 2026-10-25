import SwiftUI

/// First-launch setup: pick where Mike's thinking happens. Also reachable from
/// Settings later. Keys and tokens go to the iPhone Keychain only - never into
/// chat, logs, or the repo.
struct OnboardingView: View {
    @EnvironmentObject var store: ProviderStore
    @Environment(\.dismiss) private var dismiss

    @State private var groqKeyInput = ""
    @State private var groqStatus: String?
    @State private var groqBusy = false
    @State private var groqSaved = false

    @State private var backendURLInput = ""
    @State private var backendTokenInput = ""
    @State private var backendStatus: String?
    @State private var backendBusy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Pick where Mike's thinking happens. You can switch later in Settings - your chats and settings stay, and Mike never switches on its own.")
                        .foregroundStyle(.secondary)
                    localCard
                    groqCard
                    backendCard
                    Text("Keys and tokens are stored in the iPhone Keychain. They never go into a chat, a log, or the code.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Set up Mike")
        }
    }

    private var localCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("On this iPhone", systemImage: "iphone").font(.headline)
            Text("Gemma 4 E2B, a small model that runs fully on the phone and works offline. The exact download size is shown before anything downloads.")
                .font(.subheadline)
            Text("Not in this build yet: the on-device runtime is still being wired up. If you pick this now, chat will say so honestly instead of pretending to work.")
                .font(.footnote)
                .foregroundStyle(.orange)
            Button("Choose on-device") {
                store.select(.local); dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var groqCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Groq API", systemImage: "bolt").font(.headline)
            Text("Fast cloud replies via Groq's API. You paste your own key here, privately - it is stored in the iPhone Keychain and sent only to Groq (api.groq.com) when you chat.")
                .font(.subheadline)
            SecureField("gsk_...", text: $groqKeyInput)
                .textFieldStyle(.roundedBorder)
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            HStack {
                Button(groqBusy ? "Testing..." : "Save & test") {
                    groqBusy = true; groqStatus = nil
                    let key = groqKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task {
                        let verdict = await GroqClient.validate(key: key)
                        if verdict.hasPrefix("Key works") {
                            KeychainStore.save(key, account: KeychainStore.groqKey)
                            groqSaved = true
                        }
                        groqStatus = verdict
                        groqBusy = false
                    }
                }
                .buttonStyle(.bordered)
                .disabled(groqBusy || groqKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Save without testing") {
                    let key = groqKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    KeychainStore.save(key, account: KeychainStore.groqKey)
                    groqSaved = true
                    groqStatus = "Saved, not tested. If the key is wrong, chat will show Groq's error."
                }
                .buttonStyle(.bordered)
                .disabled(groqBusy || groqKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let groqStatus { Text(groqStatus).font(.footnote).foregroundStyle(.secondary) }
            Button("Use Groq") { store.select(.groq); dismiss() }
                .buttonStyle(.borderedProminent)
                .disabled(!groqSaved)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var backendCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Your own backend", systemImage: "server.rack").font(.headline)
            Text("Connect to a Mike core you run yourself. HTTPS is required so your token is not sent in the open.")
                .font(.subheadline)
            TextField("https://your-backend.example.com", text: $backendURLInput)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            SecureField("Access token", text: $backendTokenInput)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            HStack {
                Button(backendBusy ? "Testing..." : "Save & test") {
                    backendBusy = true; backendStatus = nil
                    Task {
                        backendStatus = await testBackend()
                        backendBusy = false
                    }
                }
                .buttonStyle(.bordered)
                .disabled(backendBusy || backendURLInput.isEmpty)
                Button("Use backend") {
                    saveBackend()
                    store.select(.backend); dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(URL(string: backendURLInput)?.scheme != "https")
            }
            if URL(string: backendURLInput)?.scheme == "http" {
                Text("That URL is plain HTTP. Use HTTPS - otherwise your token travels unencrypted.")
                    .font(.footnote).foregroundStyle(.orange)
            }
            if let backendStatus { Text(backendStatus).font(.footnote).foregroundStyle(.secondary) }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func saveBackend() {
        UserDefaults.standard.set(backendURLInput, forKey: "mike.baseURL")
        let token = backendTokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty { KeychainStore.save(token, account: KeychainStore.backendToken) }
    }

    private func testBackend() async -> String {
        guard let url = URL(string: backendURLInput), url.scheme == "https" else {
            return "Enter a full HTTPS URL first."
        }
        saveBackend()
        var req = URLRequest(url: url.appendingPathComponent("status"))
        req.timeoutInterval = 15
        let token = backendTokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return "No response from that URL." }
            if http.statusCode == 401 { return "The backend rejected the token." }
            return (200..<300).contains(http.statusCode)
                ? "Connected. The backend answered /status."
                : "The URL answered with status \(http.statusCode). Saved anyway - check the path and token."
        } catch {
            return "Couldn't reach it: \(error.localizedDescription). Saved anyway."
        }
    }
}

#Preview { OnboardingView().environmentObject(ProviderStore()) }
