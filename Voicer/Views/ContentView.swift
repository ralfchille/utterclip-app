import SwiftUI

/// Main record screen (plan Phase 7): big record/stop button, result area,
/// style picker row, spinner during rewrite. Monochrome, HIG-native.
struct ContentView: View {
    @State private var viewModel = RecorderViewModel()
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                resultArea
                if viewModel.rawTranscript != nil {
                    StylePickerRow(
                        selected: viewModel.selectedStyle,
                        isDisabled: viewModel.isBusy
                    ) { style in
                        Task { await viewModel.rewrite(with: style) }
                    }
                }
                recordButton
                    .padding(.bottom, 24)
            }
            .navigationTitle("Voicer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(viewModel: viewModel)
            }
        }
        .tint(.primary)
    }

    // MARK: - Result area

    @ViewBuilder
    private var resultArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch viewModel.phase {
                case .idle:
                    statusHint
                case .recording:
                    recordingIndicator
                case .transcribing:
                    progressRow(viewModel.transcription.state == .ready
                        ? "Transcribing…" : "Finishing model setup…")
                case .rewriting, .done:
                    transcriptSection
                case .error(let message):
                    errorSection(message)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var statusHint: some View {
        VStack(spacing: 8) {
            switch viewModel.transcription.state {
            case .cold, .warming:
                readyHint
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Model loads in the background — you can record right away.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 12)
            case .failed(let message):
                VStack(spacing: 12) {
                    Label("Model failed to load", systemImage: "exclamationmark.triangle")
                        .font(.subheadline.weight(.semibold))
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                    Text("The model downloads once from huggingface.co on first launch — check your internet connection (Wi-Fi recommended, ~500 MB) and retry.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        viewModel.transcription.warmUp()
                    }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            case .ready:
                readyHint
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var readyHint: some View {
        VStack(spacing: 6) {
            Image(systemName: "mic.circle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("Tap the mic, speak, tap again.\nYour words land on the clipboard.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    @ViewBuilder
    private var transcriptSection: some View {
        if viewModel.phase == .rewriting {
            progressRow("Rewriting as \(viewModel.selectedStyle.name)…")
        }

        if let styled = viewModel.styledText, viewModel.phase == .done {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Copied — \(viewModel.selectedStyle.name)", systemImage: "doc.on.clipboard")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    markdownToggle
                }
                MarkdownView(markdown: styled)
                    .textSelection(.enabled)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassBackground(shape: RoundedRectangle(cornerRadius: 16))
        }

        if let rewriteError = viewModel.rewriteError {
            VStack(alignment: .leading, spacing: 6) {
                Label(rewriteError, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Retry rewrite") {
                    Task { await viewModel.rewrite(with: viewModel.selectedStyle) }
                }
                .font(.footnote.weight(.semibold))
            }
        }

        if let raw = viewModel.rawTranscript {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Raw transcript")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        viewModel.copyRaw()
                    } label: {
                        Label("Copy raw", systemImage: "doc.on.doc")
                            .font(.caption)
                    }
                    .accessibilityLabel("Copy raw transcript")
                }
                Text(raw)
                    .font(.callout)
                    .foregroundStyle(viewModel.styledText == nil ? .primary : .secondary)
                    .textSelection(.enabled)
            }
        }
    }

    /// Big elapsed-time counter while recording, echoing the reference app's record screen.
    private var recordingIndicator: some View {
        VStack(spacing: 24) {
            Label("Recording", systemImage: "waveform")
                .font(.subheadline.weight(.semibold))
                .symbolEffect(.variableColor.iterative)
                .foregroundStyle(.secondary)
            if let startedAt = viewModel.recorder.startedAt {
                Text(startedAt, style: .timer)
                    .font(.system(size: 64, weight: .light, design: .rounded))
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    /// Sticky copy-mode switch: off = rich copy for Docs/Mail/Word, on = raw markdown.
    /// Toggling re-copies the current result and the mode persists across recordings.
    private var markdownToggle: some View {
        Button {
            viewModel.toggleMarkdownCopy()
        } label: {
            Label("Markdown", systemImage: "number")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(viewModel.copyAsMarkdown ? Color(.systemBackground) : .secondary)
                .background {
                    if viewModel.copyAsMarkdown {
                        Capsule().fill(.primary)
                    } else {
                        Capsule().strokeBorder(.tertiary)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewModel.copyAsMarkdown
            ? "Markdown copy on — tap to copy formatted text instead"
            : "Copy as markdown")
    }

    private func progressRow(_ text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(text)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private func errorSection(_ message: String) -> some View {
        VStack(spacing: 12) {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .multilineTextAlignment(.leading)
            Button("Dismiss") {
                viewModel.dismissError()
                viewModel.transcription.warmUp() // no-op unless the model load failed
            }
            .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Record button

    /// Recording only needs the mic — it stays available while the model warms up;
    /// transcription waits for the load. Only a failed load (or mid-flow work) blocks it.
    private var recordUnavailable: Bool {
        if case .failed = viewModel.transcription.state { return true }
        return viewModel.isBusy
    }

    private var recordButton: some View {
        Button {
            Task {
                if viewModel.recorder.isRecording {
                    await viewModel.stopAndProcess()
                } else {
                    await viewModel.record()
                }
            }
        } label: {
            Image(systemName: viewModel.recorder.isRecording ? "stop.fill" : "mic.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(viewModel.recorder.isRecording ? Color(.systemBackground) : .primary)
                .frame(width: 84, height: 84)
                .background {
                    if viewModel.recorder.isRecording {
                        Circle().fill(.primary)
                    }
                }
                .glassBackground(shape: Circle())
        }
        .buttonStyle(.plain)
        .disabled(recordUnavailable)
        .opacity(recordUnavailable ? 0.4 : 1)
        .accessibilityLabel(viewModel.recorder.isRecording ? "Stop recording" : "Start recording")
        .animation(.snappy, value: viewModel.recorder.isRecording)
    }
}

#Preview {
    ContentView()
}
