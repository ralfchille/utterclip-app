import Combine
import SwiftUI
import UtterclipCore

/// Main record screen (plan Phase 7): big record/stop button, result area,
/// style picker row, spinner during rewrite. Monochrome, HIG-native.
struct ContentView: View {
    @State private var viewModel = RecorderViewModel()
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var editTarget: EditTarget?

    /// Which text the editor is currently editing.
    private enum EditTarget: String, Identifiable {
        case styled, raw
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                resultArea
                // Always present: before a recording the highlighted pill is the style the
                // recording will be rewritten in; afterwards tapping one re-runs the rewrite.
                StylePickerRow(
                    selected: viewModel.selectedStyle,
                    isDisabled: viewModel.isBusy
                ) { style in
                    viewModel.select(style)
                }
                .padding(.bottom, 10) // sit a touch higher above the record button
                recordButton
                    .padding(.bottom, 24)
            }
            .navigationTitle("Utterclip")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .barLeading) {
                    Button {
                        showHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("History")
                }
                ToolbarItem(placement: .barTrailing) {
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
            .sheet(isPresented: $showHistory) {
                HistoryView(viewModel: viewModel)
            }
            .onOpenURL { url in
                // utterclip://record — from the Home Screen widget or the Control Center button.
                // (The Mac app receives URLs in its AppDelegate and posts the notification above.)
                guard url.host == "record", !viewModel.recorder.isRecording, !recordUnavailable else { return }
                Task { await viewModel.record() }
            }
            // Menu items and keyboard shortcuts (macOS) drive the same actions as the buttons.
            .onReceive(NotificationCenter.default.publisher(for: .utterclipToggleRecording)) { _ in
                toggleRecording()
            }
            .onReceive(NotificationCenter.default.publisher(for: .utterclipStartRecording)) { _ in
                guard !viewModel.recorder.isRecording, !recordUnavailable else { return }
                Task { await viewModel.record() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .utterclipContinueRecording)) { _ in
                guard viewModel.phase == .done, viewModel.rawTranscript != nil else { return }
                Task { await viewModel.continueRecording() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .utterclipShowHistory)) { _ in
                showHistory = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .utterclipShowSettings)) { _ in
                showSettings = true
            }
            .editorPresentation(item: $editTarget) { target in
                switch target {
                case .styled:
                    EditorView(
                        title: "Edit \(viewModel.selectedStyle.name)",
                        initialText: viewModel.styledText ?? ""
                    ) { viewModel.applyStyledEdit($0) }
                case .raw:
                    EditorView(
                        title: "Edit transcript",
                        initialText: viewModel.rawTranscript ?? ""
                    ) { viewModel.applyRawEdit($0) }
                }
            }
        }
        .tint(.primary)
    }

    // MARK: - Result area

    /// Idle status sits just above the record button (the Figma idle frame anchors the
    /// hint to the bottom, no icon); every other phase scrolls its content from the top.
    @ViewBuilder
    private var resultArea: some View {
        if viewModel.phase == .idle {
            // Three equal spacers land the loading indicator at the upper third while the
            // hint stays anchored above the record button.
            VStack(spacing: 0) {
                Spacer()
                modelLoadingIndicator
                Spacer()
                Spacer()
                statusHint
            }
            .padding(.horizontal)
            .padding(.bottom, 8) // the style pills sit between the hint and the record button
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.snappy, value: viewModel.transcription.state)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch viewModel.phase {
                    case .idle:
                        EmptyView() // handled above
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
    }

    /// Spinner over centered text while the model is still loading; gone once it's ready.
    @ViewBuilder
    private var modelLoadingIndicator: some View {
        switch viewModel.transcription.state {
        case .cold, .warming:
            VStack(spacing: 10) {
                ProgressView()
                Text("Model loads in the background — you can record right away.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true) // wrap, never truncate
            }
            .frame(maxWidth: .infinity)
        case .ready, .failed:
            EmptyView()
        }
    }

    @ViewBuilder
    private var statusHint: some View {
        VStack(spacing: 8) {
            switch viewModel.transcription.state {
            case .failed(let message):
                VStack(spacing: 12) {
                    Label("Model failed to load", systemImage: "exclamationmark.triangle")
                        .font(.subheadline.weight(.semibold))
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                    Text("The model downloads once from huggingface.co on first launch — check your internet connection (Wi-Fi recommended, ~220 MB) and retry.")
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
            case .cold, .warming, .ready:
                noticeRow
                readyHint
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Text-only hint (the Figma idle frame drops the mic glyph); `resultArea` anchors it
    /// above the record button, so no top padding here.
    private var readyHint: some View {
        Text(PlatformText.readyHint)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    /// Non-error status after a recording with no speech in it (Whisper's
    /// "[BLANK_AUDIO]"); clears with the next recording.
    @ViewBuilder
    private var noticeRow: some View {
        if let notice = viewModel.notice {
            Label(notice, systemImage: "waveform.slash")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var transcriptSection: some View {
        noticeRow
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
                    editButton("Edit formatted text") { editTarget = .styled }
                    markdownToggle
                }
                MarkdownView(markdown: styled)
                    .textSelection(.enabled)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassBackground(shape: RoundedRectangle(cornerRadius: 16))
        }

        if viewModel.rewriteNeedsKey, viewModel.phase == .done {
            apiKeyInfoCard
        }

        if let rewriteError = viewModel.rewriteError {
            VStack(alignment: .leading, spacing: 6) {
                Label(rewriteError, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Retry rewrite") {
                    viewModel.rewrite(with: viewModel.selectedStyle)
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
                    editButton("Edit raw transcript") { editTarget = .raw }
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
            .padding(.horizontal) // align with the styled card's inner content
        }
    }

    /// Takes the styled result's place when no working API key is stored: what's needed,
    /// where to add it, and that the raw transcript is already copied.
    private var apiKeyInfoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Styled rewrites need an API key", systemImage: "key")
                .font(.subheadline.weight(.semibold))
            Text(viewModel.onDeviceAvailable
                ? "Add an Anthropic, OpenAI, Google Gemini or Groq key in Settings — or rewrite on \(PlatformText.deviceName) with Apple Intelligence, where nothing leaves the device. Your raw transcript is already on the clipboard."
                : "Add an Anthropic, OpenAI, Google Gemini or Groq key in Settings. Your raw transcript is already on the clipboard.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                Button("Open Settings") { showSettings = true }
                if viewModel.onDeviceAvailable {
                    Button("Use on-device model") {
                        viewModel.switchToOnDeviceModel()
                    }
                }
            }
            .font(.footnote.weight(.semibold))
            // Only worth a line on devices that could run the model but aren't ready (Apple
            // Intelligence off, model downloading); on ineligible devices say nothing.
            if viewModel.onDeviceSupported, !viewModel.onDeviceAvailable,
               let reason = viewModel.onDeviceUnavailabilityReason {
                Text("On-device model: \(reason)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackground(shape: RoundedRectangle(cornerRadius: 16))
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
            WaveformView(levels: viewModel.recorder.levels)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    /// Sticky copy-mode switch: off = plain text (markdown stripped), on = raw markdown.
    /// Toggling re-copies the current result and the mode persists across recordings.
    private var markdownToggle: some View {
        Button {
            viewModel.toggleMarkdownCopy()
        } label: {
            HStack(spacing: 2) { // half of Label's default icon–title gap
                Image(systemName: "number")
                Text("Markdown")
            }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(viewModel.copyAsMarkdown ? Color.appBackground : .secondary)
                .background {
                    if viewModel.copyAsMarkdown {
                        Capsule().fill(.primary)
                    } else {
                        Capsule().strokeBorder(.tertiary)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewModel.copyAsMarkdown
            ? "Markdown copy on — tap to copy plain text instead"
            : "Copy as markdown")
    }

    /// Compact monochrome "Edit" affordance opening the full-screen editor.
    private func editButton(_ accessibilityLabel: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label("Edit", systemImage: "square.and.pencil")
                .font(.caption.weight(.semibold))
        }
        .accessibilityLabel(accessibilityLabel)
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

    /// One action for the button, the ⌘R menu item and the URL scheme.
    private func toggleRecording() {
        if viewModel.recorder.isRecording {
            viewModel.stopAndProcess()
        } else if !recordUnavailable {
            Task { await viewModel.record() }
        }
    }

    private var recordButton: some View {
        Button {
            toggleRecording()
        } label: {
            recordButtonLabel
        }
        .buttonStyle(.plain)
        .disabled(recordUnavailable)
        .opacity(recordUnavailable ? 0.4 : 1)
        .accessibilityLabel(viewModel.recorder.isRecording ? "Stop recording" : "Start recording")
        .overlay(alignment: .leading) {
            if viewModel.recorder.isRecording || viewModel.isBusy {
                cancelButton
                    .offset(x: -80)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .overlay(alignment: .trailing) {
            if viewModel.phase == .done, viewModel.rawTranscript != nil {
                continueButton
                    .offset(x: 80)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(.snappy, value: viewModel.recorder.isRecording)
        .animation(.snappy, value: viewModel.phase)
    }

    /// Stop state uses a solid fill without the glass layer — glass over the filled
    /// circle frosts it and kills the contrast against the background.
    @ViewBuilder
    private var recordButtonLabel: some View {
        let icon = Image(systemName: viewModel.recorder.isRecording ? "stop.fill" : "mic.fill")
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(viewModel.recorder.isRecording ? Color.appBackground : .primary)
            .frame(width: 84, height: 84)
        // Explicit hit shape: on macOS the glass/background layers don't count as content,
        // so without it only the glyph's own pixels would take the click.
        if viewModel.recorder.isRecording {
            icon.background(Circle().fill(.primary)).contentShape(Circle())
        } else {
            icon.glassBackground(shape: Circle()).contentShape(Circle())
        }
    }

    /// Abandons the recording, transcription or rewrite in progress; visible while any is.
    private var cancelButton: some View {
        Button {
            viewModel.cancel()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 56, height: 56)
                .glassBackground(shape: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewModel.recorder.isRecording ? "Cancel recording" : "Cancel")
    }

    /// Appends another dictation to the transcript on screen; only visible with a result.
    private var continueButton: some View {
        Button {
            Task { await viewModel.continueRecording() }
        } label: {
            Image(systemName: "mic.badge.plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 56, height: 56)
                .glassBackground(shape: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isBusy)
        .accessibilityLabel("Continue dictating")
    }
}

#Preview {
    ContentView()
}
