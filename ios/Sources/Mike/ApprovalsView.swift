import SwiftUI

struct ApprovalsView: View {
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var store: ProviderStore
    @EnvironmentObject var agent: AgentStore
    @State private var remote: [Approval] = []
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            Group {
                if store.provider == .backend {
                    backendList
                } else {
                    localList
                }
            }
            .navigationTitle("Approvals")
            .refreshable { if store.provider == .backend { await reload() } }
            .task { if store.provider == .backend { await reload() } }
        }
    }

    @ViewBuilder private var localList: some View {
        let pending = agent.approvals.filter { $0.status == .pending }
        if pending.isEmpty {
            ContentUnavailableView("Nothing waiting",
                systemImage: "checkmark.shield",
                description: Text("This is the real queue on this phone, not a guess. When Mike wants to remember something or set a reminder, it waits here until you say yes."))
        } else {
            List {
                ForEach(pending) { approval in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(approval.title).font(.headline)
                        Text(approval.detail).font(.subheadline).foregroundStyle(.secondary)
                        HStack {
                            Button("Approve") { answer(approval, true) }.buttonStyle(.borderedProminent)
                            Button("Deny", role: .destructive) { answer(approval, false) }.buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder private var backendList: some View {
        if loadError != nil && remote.isEmpty {
            ContentUnavailableView("Can't reach your backend",
                systemImage: "exclamationmark.triangle",
                description: Text("The backend you set isn't answering. Pull to retry once it is up."))
        } else if remote.isEmpty {
            ContentUnavailableView("Nothing waiting",
                systemImage: "checkmark.shield",
                description: Text("Connected to your backend - this is a real empty queue, not a guess."))
        } else {
            List {
                ForEach(remote) { approval in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(approval.summary).font(.headline)
                        Text(approval.detail).font(.subheadline).foregroundStyle(.secondary)
                        HStack {
                            Button("Approve") { answerRemote(approval, true) }.buttonStyle(.borderedProminent)
                            Button("Deny", role: .destructive) { answerRemote(approval, false) }.buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func answer(_ approval: LocalApproval, _ approve: Bool) {
        if let resolved = agent.resolve(approval.id, approved: approve) {
            if approve { Tooling.executeApproved(resolved, store: agent) }
            else { agent.log("approval", "Denied: \(resolved.title)") }
        }
    }

    private func reload() async {
        do { remote = try await api.pendingApprovals(); loadError = nil }
        catch { loadError = "Backend unreachable - pull to retry." }
    }

    private func answerRemote(_ approval: Approval, _ approve: Bool) {
        Task {
            try? await api.answer(approval, approve: approve)
            await reload()
        }
    }
}

#Preview { ApprovalsView().environmentObject(APIClient()).environmentObject(ProviderStore()).environmentObject(AgentStore()) }
