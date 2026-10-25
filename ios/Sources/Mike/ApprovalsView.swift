import SwiftUI

struct ApprovalsView: View {
    @EnvironmentObject var api: APIClient
    @State private var approvals: [Approval] = []
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            Group {
                if approvals.isEmpty {
                    ContentUnavailableView("Nothing waiting",
                        systemImage: "checkmark.shield",
                        description: Text(loadError ?? "When Mike wants to message someone, spend money or change himself, it shows up here first."))
                } else {
                    List {
                        ForEach(approvals) { approval in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(approval.summary).font(.headline)
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
            .navigationTitle("Approvals")
            .refreshable { await reload() }
            .task { await reload() }
        }
    }

    private func reload() async {
        do { approvals = try await api.pendingApprovals(); loadError = nil }
        catch { loadError = "Core unreachable - pull to retry." }
    }

    private func answer(_ approval: Approval, _ approve: Bool) {
        Task {
            try? await api.answer(approval, approve: approve)
            await reload()
        }
    }
}

#Preview { ApprovalsView().environmentObject(APIClient()) }
