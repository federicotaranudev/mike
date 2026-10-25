import SwiftUI

struct ActivityView: View {
    @EnvironmentObject var api: APIClient
    @State private var entries: [ActivityEntry] = []
    @State private var showStopConfirm = false

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty {
                    ContentUnavailableView("No activity yet", systemImage: "list.bullet.rectangle",
                        description: Text("Everything Mike does lands here."))
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
        entries = (try? await api.activity()) ?? []
    }
}

#Preview { ActivityView().environmentObject(APIClient()) }
