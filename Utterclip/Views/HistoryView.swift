import SwiftUI
import UtterclipCore

/// Browsable log of past dictations. Tapping an entry restores it as the current
/// result on the main screen; rows can be deleted (swipe on iOS, context menu on both),
/// and the whole log cleared.
struct HistoryView: View {
    let viewModel: RecorderViewModel

    @State private var store = HistoryStore.shared
    @State private var confirmClear = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if store.entries.isEmpty {
                    ContentUnavailableView(
                        "No dictations yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Finished dictations show up here so you can go back to them.")
                    )
                } else {
                    entryList
                }
            }
            .navigationTitle("History")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .barLeading) {
                    if !store.entries.isEmpty {
                        Button("Clear", role: .destructive) {
                            confirmClear = true
                        }
                        // Anchored to the button so the popover's tail points at Clear.
                        .confirmationDialog(
                            "Delete all dictations?",
                            isPresented: $confirmClear,
                            titleVisibility: .visible
                        ) {
                            Button("Delete All", role: .destructive) {
                                store.clear()
                            }
                        }
                    }
                }
                ToolbarItem(placement: .barTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .tint(.primary)
        .sheetFrame(minWidth: 440, minHeight: 520)
    }

    private var entryList: some View {
        List {
            ForEach(store.entries) { entry in
                Button {
                    viewModel.restore(entry)
                    dismiss()
                } label: {
                    row(for: entry)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Delete", role: .destructive) { delete(entry) }
                }
            }
            .onDelete { store.delete(at: $0) }
        }
        .listStyle(.plain)
    }

    private func delete(_ entry: HistoryEntry) {
        guard let index = store.entries.firstIndex(where: { $0.id == entry.id }) else { return }
        store.delete(at: IndexSet(integer: index))
    }

    private func row(for entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.date, format: .relative(presentation: .named))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let styleID = entry.styleID,
                   let name = StyleStore.shared.styleIfPresent(withID: styleID)?.name {
                    Text(name)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().strokeBorder(.tertiary))
                        .foregroundStyle(.secondary)
                }
            }
            Text(entry.rawTranscript)
                .font(.callout)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
