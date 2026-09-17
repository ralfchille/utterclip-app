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
    @Environment(\.panelDismiss) private var panelDismiss

    var body: some View {
        SheetNavigation {
            VStack(spacing: 0) {
                #if os(macOS)
                MacHeader(title: "History") {
                    if !store.entries.isEmpty {
                        Button("Clear") { confirmClear = true }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            // Anchored to the button, so the popover's tail points at Clear.
                            .confirmationDialog("Delete all dictations?", isPresented: $confirmClear, titleVisibility: .visible) {
                                Button("Delete All", role: .destructive) { clearAfterDialogCloses() }
                            }
                    }
                    Button {
                        close()
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .accessibilityLabel("Close")
                    .keyboardShortcut(.cancelAction)
                }
                #endif
                content
            }
            .ignoreHiddenTitleBar()
            .barChrome(title: "History") {
                ToolbarItem(placement: .sheetDestructive) {
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
                            Button("Delete All", role: .destructive) { clearAfterDialogCloses() }
                        }
                    }
                }
                ToolbarItem(placement: .sheetCancel) {
                    Button {
                        close()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .tint(.primary)
        .onAppear { store.reload() } // a CloudKit import may have landed since the last look
    }

    /// Empties the log a beat after the dialog has closed. Clearing immediately removes the
    /// Clear button — the dialog's own anchor — and a dialog whose anchor disappears mid-
    /// dismissal stays on screen with nothing left to confirm.
    private func clearAfterDialogCloses() {
        confirmClear = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            store.clear()
        }
    }

    @ViewBuilder
    private var content: some View {
        Group {
                if store.entries.isEmpty {
                    ContentUnavailableView(
                        "No dictations yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Finished dictations show up here so you can go back to them.")
                    )
                    // Fill the sheet: sized to its content, the placeholder would leave the
                    // navigation bar floating in a tall empty band above it on macOS.
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    entryList
                }
        }
    }

    private var entryList: some View {
        #if os(macOS)
        // A plain scroll view rather than List: the Mac List sits on a table view that
        // estimates row heights, and multi-line rows growing after the first layout left
        // the top entry scrolled half out of view. Same rows, same hairlines, no surprises.
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(store.entries) { entry in
                    Button {
                        viewModel.restore(entry)
                        close()
                    } label: {
                        row(for: entry)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Delete", role: .destructive) { store.delete(id: entry.id) }
                    }
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 1)
                        .padding(.leading, 20)
                }
            }
            .padding(.top, 4)
        }
        #else
        List {
            ForEach(store.entries) { entry in
                Button {
                    viewModel.restore(entry)
                    close()
                } label: {
                    row(for: entry)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Delete", role: .destructive) { store.delete(id: entry.id) }
                }
            }
            .onDelete { store.delete(at: $0) }
        }
        .listStyle(.plain)
        #endif
    }

    /// A Mac panel closes through the binding that presented it; everything else through the
    /// system's own dismissal.
    private func close() {
        if let panelDismiss { panelDismiss() } else { dismiss() }
    }

    private func row(for entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) { // air between the date/style line and the text
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
                .font(PlatformFont.historyTranscript)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
