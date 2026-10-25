import SwiftUI

struct ActivityView: View {
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var store: ProviderStore
    @EnvironmentObject var agent: AgentStore
    @State private var remote: [ActivityEntry] = []
    @State private var showStopConfirm = false
    @State private var loadFailed = false

    var body: some View {
        NavigationStack {
            Group {
                if store.provider == .backend {
                    backendList
                } else {
                    localList
                }
            }
            .navigationTitle("Activity")
            .refreshable { if store.provider == .backend { await reload() } }
            .task { if store.provider == .backend { await reload() } }
            .toolbar {
                if store.provider == .backend {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Stop", role: .destructive) { showStopConfirm = true }
                    }
                }
            }
            .confirmationDialog("Stop Mike?", isPresented: $showStopConfirm, titleVisibility: .visible) {
                Button("Stop Mike", role: .destructive) {
                    Task { try? await api.stopMike() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Mike pauses everything until you start him again. Nothing keeps running in the background.")
            }
        }
    }

    @ViewBuilder private var localList: some View {
        if agent.activity.isEmpty {
            ContentUnavailableView("No activity yet", systemImage: "list.bullet.rectangle",
                description: Text("This is the real on-device log - empty because Mike hasn't done anything yet, not because something failed to load. Tool runs, approvals and downloads land here."))
        } else {
            List {
                ForEach(agent.activity) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.summary)
                        Text(entry.kind.uppercased())
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder private var backendList: some View {
        if loadFailed && remote.isEmpty {
            ContentUnavailableView("Can't reach your backend", systemImage: "exclamationmark.triangle",
                description: Text("The backend you set isn't answering. Pull to retry once it is up."))
        } else {
            List {
                ForEach(remote) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.summary)
                        Text(entry.kind.uppercased())
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func reload() async {
        do {
            remote = try await api.activity()
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }
}

#Preview { ActivityView().environmentObject(APIClient()).environmentObject(ProviderStore()).environmentObject(AgentStore()) }
