import SwiftUI

struct ChatView: View {
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var providers: ProviderStore
    @EnvironmentObject var agent: AgentStore
    @EnvironmentObject var models: ModelManager
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
    @FocusState private var composerFocused: Bool

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
                    .onTapGesture { composerFocused = false }
                    .onChange(of: messages.count) { _, _ in
                        // Only auto-scroll once a conversation is going; on a
                        // fresh screen this used to shove the greeting up
                        // under the navigation bar when the keyboard opened.
                        if messages.count > 1, let last = messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                // iMessage-style composer: one translucent capsule holding the
                // field and a round send button. No placeholder buttons - only
                // controls that do something real are shown.
                HStack(spacing: 6) {
                    TextField("Message Mike...", text: $draft, axis: .vertical)
                        .focused($composerFocused)
                        .lineLimit(1...4)
                        .padding(.leading, 14)
                    Button(action: send) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                        ? Color.gray.opacity(0.5) : Color.accentColor)
                            .clipShape(Circle())
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || thinking)
                    .padding(.trailing, 6)
                }
                .padding(.vertical, 6)
                .background(Color(.secondarySystemBackground).opacity(0.9))
                .clipShape(Capsule())
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
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
                    let history = messages.suffix(20).map {
                        Tooling.ToolMsg(role: $0.role == .user ? "user" : "assistant", content: $0.text)
                    }
                    let reply = try await AgentLoop.run(key: key, conversation: history, store: agent)
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
                switch models.state {
                case .downloaded:
                    do {
                        let reply = try await LocalInference.reply(to: text, modelPath: models.modelFileURL.path)
                        agent.log("local", "Replied on-device with Gemma 4 E2B")
                        messages.append(ChatMessage(role: .mike, text: reply))
                    } catch {
                        messages.append(ChatMessage(role: .mike,
                            text: "The local model failed to run: \(error.localizedDescription) Nothing was faked - switch provider in Settings if you want to chat right now."))
                    }
                default:
                    messages.append(ChatMessage(role: .mike,
                        text: "The on-device model isn't downloaded yet. Get it in Settings (2.0 GB, runs on the iPhone GPU - first reply loads it, which takes a while, and it's untested on iPhone 13). No download, no fake replies."))
                }
            case nil:
                messages.append(ChatMessage(role: .mike,
                    text: "Setup isn't finished yet. Pick where Mike thinks on the setup screen."))
            }
        }
    }
}

#Preview { ChatView().environmentObject(APIClient()).environmentObject(ProviderStore()).environmentObject(AgentStore()).environmentObject(ModelManager()) }
