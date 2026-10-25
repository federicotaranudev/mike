import SwiftUI

struct ChatView: View {
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var providers: ProviderStore
    #if SIM_FORCE_LOCAL
    // Screenshot variant: show the honest "not wired yet" state up front.
    @State private var messages: [ChatMessage] = [
        ChatMessage(role: .mike, text: "Hey, I'm Mike. Ask me something, or tell me what to remember. Watching things on my own isn't built yet - when it is, I'll tell you here."),
        ChatMessage(role: .mike, text: "The on-device model isn't wired into this build yet - I won't fake a reply before the runtime lands. Switch provider in Settings if you want to chat right now.")
    ]
    #else
    @State private var messages: [ChatMessage] = [
        ChatMessage(role: .mike, text: "Hey, I'm Mike. Ask me something, or tell me what to remember. Watching things on my own isn't built yet - when it is, I'll tell you here.")
    ]
    #endif
    @State private var draft = ""
    @State private var thinking = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(messages) { msg in
                                bubble(msg).id(msg.id)
                            }
                            if thinking {
                                ProgressView().padding(.leading, 12)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) { _, _ in
                        // Only auto-scroll once a conversation is going; on a
                        // fresh screen this used to shove the greeting up
                        // under the navigation bar when the keyboard opened.
                        if messages.count > 1, let last = messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                HStack(spacing: 8) {
                    TextField("Message Mike...", text: $draft, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || thinking)
                }
                .padding()
            }
            .navigationTitle("Mike")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func bubble(_ msg: ChatMessage) -> some View {
        HStack {
            if msg.role == .user { Spacer(minLength: 40) }
            Text(msg.text)
                .padding(10)
                .background(msg.role == .user ? Color.accentColor.opacity(0.85) : Color(.secondarySystemBackground))
                .foregroundStyle(msg.role == .user ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            if msg.role == .mike { Spacer(minLength: 40) }
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        messages.append(ChatMessage(role: .user, text: text))
        thinking = true
        Task {
            defer { thinking = false }
            switch providers.provider {
            case .groq:
                guard let key = KeychainStore.load(KeychainStore.groqKey) else {
                    messages.append(ChatMessage(role: .mike,
                        text: "No Groq key saved on this phone. Add it on the setup screen or in Settings - it never goes through this chat."))
                    return
                }
                do {
                    var history = [GroqClient.Msg(role: "system",
                        content: "You are Mike, a personal assistant. Be concise, and honest about what you can't do.")]
                    history += messages.suffix(20).map {
                        GroqClient.Msg(role: $0.role == .user ? "user" : "assistant", content: $0.text)
                    }
                    let reply = try await GroqClient.chat(key: key, history: history)
                    messages.append(ChatMessage(role: .mike, text: reply))
                } catch {
                    messages.append(ChatMessage(role: .mike, text: error.localizedDescription))
                }
            case .backend:
                do {
                    let reply = try await api.sendChat(text)
                    messages.append(ChatMessage(role: .mike, text: reply))
                } catch {
                    messages.append(ChatMessage(role: .mike,
                        text: "Can't reach the backend you set. Check the URL and token in Settings, and that the core is running."))
                }
            case .local:
                messages.append(ChatMessage(role: .mike,
                    text: "The on-device model isn't wired into this build yet - I won't fake a reply before the runtime lands. Switch provider in Settings if you want to chat right now."))
            case nil:
                messages.append(ChatMessage(role: .mike,
                    text: "Setup isn't finished yet. Pick where Mike thinks on the setup screen."))
            }
        }
    }
}

#Preview { ChatView().environmentObject(APIClient()).environmentObject(ProviderStore()) }
