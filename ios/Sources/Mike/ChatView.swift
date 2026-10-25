import SwiftUI

struct ChatView: View {
    @EnvironmentObject var api: APIClient
    @State private var messages: [ChatMessage] = [
        ChatMessage(role: .mike, text: "Hey, I'm Mike. Ask me something, or tell me what to remember. Watching things on my own isn't built yet - when it is, I'll tell you here.")
    ]
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
                        if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
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
            do {
                let reply = try await api.sendChat(text)
                messages.append(ChatMessage(role: .mike, text: reply))
            } catch {
                messages.append(ChatMessage(role: .mike,
                    text: "Can't reach my core on your PC right now. Check the tunnel URL in Settings and that the core is running."))
            }
        }
    }
}

#Preview { ChatView().environmentObject(APIClient()) }
