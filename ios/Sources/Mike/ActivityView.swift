import SwiftUI

struct ActivityView: View {
    @EnvironmentObject var api: APIClient
    @State private var entries: [ActivityEntry] = []
    @State private var showStopConfirm = false
    @State private var loadFailed = false

    var body: some View {
        NavigationStack {
            List {
                if loadFailed && entries.isEmpty {
                    ContentUnavailableView("Can't reach Mike's core", systemImage: "exclamationmark.triangle",
                        description: Text("Offline - recent activity is unknown, not necessarily empty. Pull to retry once the core is up."))
                } else if entries.isEmpty {
                    ContentUnavailableView("No activity yet", systemImage: "list.bullet.rectangle",
                        description: Text("Connected to the core - this is a real empty log. Everything Mike does lands here."))
                } else {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.summary)
                            Text(entry.kind.uppercased())
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Activity")
            .refreshable { await reload() }
            .task { await reload() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Stop", role: .destructive) { showStopConfirm = true }
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

    private func reload() async {
        do {
            entries = try await api.activity()
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }
}

#Preview { ActivityView().environmentObject(APIClient()) }
