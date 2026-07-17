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
                    progressRow("Transcribing…")
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
                progressRow("Warming up the transcription model…")
                Text("First launch downloads the model once; afterwards it's instant.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            case .failed(let message):
                errorSection("Model failed to load: \(message)")
            case .ready:
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
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var transcriptSection: some View {
        if viewModel.phase == .rewriting {
            progressRow("Rewriting as \(viewModel.selectedStyle.name)…")
        }

        if let styled = viewModel.styledText, viewModel.phase == .done {
            VStack(alignment: .leading, spacing: 6) {
                Label("Copied — \(viewModel.selectedStyle.name)", systemImage: "doc.on.clipboard")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(styled)
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
        .disabled(viewModel.transcription.state != .ready || viewModel.isBusy)
        .opacity(viewModel.transcription.state == .ready && !viewModel.isBusy ? 1 : 0.4)
        .accessibilityLabel(viewModel.recorder.isRecording ? "Stop recording" : "Start recording")
        .animation(.snappy, value: viewModel.recorder.isRecording)
    }
}

#Preview {
    ContentView()
}
