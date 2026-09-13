import Combine
import HighlightedTextEditor
import SwiftUI
import UtterclipCore

/// Main record screen (plan Phase 7): big record/stop button, result area,
/// style picker row, spinner during rewrite. Monochrome, HIG-native.
struct ContentView: View {
    @State private var viewModel = RecorderViewModel()
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var editTarget: EditTarget?
    /// What the result card's label is saying: at rest it names the style, while you type it
    /// says so, and it confirms each time the text goes back on the clipboard.
    private enum ResultLabel: Equatable { case idle, writing, copied }
    @State private var resultLabel: ResultLabel = .idle
    /// Copies a moment after you stop typing, so an edit needs no button at all.
    @State private var copyAfterTyping: Task<Void, Never>?
    /// The editor grows with the text it holds, up to whatever the window leaves above the
    /// pills; it never shrinks back while an edit is in progress, so lines do not jump.
    @State private var editorHeight: CGFloat = 0
    @State private var editorCeiling: CGFloat = 0
    #if os(macOS)
    @State private var pasteBack = PasteBack.shared
    @State private var mac = MacPreferences.shared
    /// The result card is edited where it sits rather than in a panel; this holds the draft
    /// until Done, so Cancel can leave the result untouched.
    @State private var styledDraft: String?
    #endif

    /// Which text the editor is currently editing.
    private enum EditTarget: String, Identifiable, Hashable {
        case styled, raw
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                #if os(macOS)
                // The Mac window has no title bar; this row is its header.
                MacHeader(title: "Utterclip") {
                    Button {
                        showHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("History")
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                    // Two sizes: a panel to dictate into, and room to read and edit in.
                    Button {
                        AppDelegate.shared?.toggleWindowSize()
                    } label: {
                        Image(systemName: mac.isWindowExpanded
                              ? "arrow.down.right.and.arrow.up.left"
                              : "arrow.up.left.and.arrow.down.right")
                    }
                    .accessibilityLabel(mac.isWindowExpanded ? "Smaller window" : "Bigger window")
                    // Back to the menu bar without having to aim for the status item.
                    Button {
                        AppDelegate.shared?.hideWindow()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
                #endif
                resultArea
                    .overlay(alignment: .top) {
                        // Mac: the phone has something — a recording under way or a finished
                        // dictation one tap away. Nothing loads until it is tapped.
                        if let update = viewModel.phoneUpdate {
                            PhoneUpdateBlob(update: update,
                                            claim: { viewModel.claimPhoneUpdate() },
                                            dismiss: { viewModel.dismissPhoneUpdate() })
                                .padding(.top, 4)
                                .padding(.horizontal) // the style pills' margin
                                .transition(.scale(scale: 0.6).combined(with: .opacity))
                        }
                    }
                    .animation(.spring(duration: 0.45, bounce: 0.35), value: viewModel.phoneUpdate)
            #if os(macOS)
            .animation(.spring(duration: 0.35, bounce: 0.2), value: pasteBack.offeredAppName)
            #endif
                // Always present: before a recording the highlighted pill is the style the
                // recording will be rewritten in; afterwards tapping one re-runs the rewrite.
                StylePickerRow(
                    selected: viewModel.selectedStyle,
                    isDisabled: viewModel.isBusy
                ) { style in
                    viewModel.select(style)
                }
                .padding(.bottom, 10) // sit a touch higher above the record button
                #if os(macOS)
                // A dictation started with the shortcut waits under the record button until it
                // is sent on, so the result can be read, edited or re-styled first.
                recordButton
                    .padding(.bottom, pasteBack.offeredAppName == nil ? 24 : 16)
                if let appName = pasteBack.offeredAppName {
                    PasteBackBar(appName: appName,
                                 paste: { pasteBack.paste() },
                                 dismiss: { pasteBack.disarm() })
                        .padding(.horizontal) // the style pills' margin
                        .padding(.bottom, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                #else
                recordButton
                    .padding(.bottom, 24)
                #endif
            }
            .ignoreHiddenTitleBar()
            .barChrome(title: "Utterclip") {
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
            .panel(isPresented: $showSettings) {
                SettingsView(viewModel: viewModel)
            }
            .panel(isPresented: $showHistory) {
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
            .onChange(of: viewModel.recorder.isRecording, initial: true) { _, isRecording in
                RecordingState.isRecording = isRecording // for the Mac status item's click logic
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
            .task {
                #if os(macOS)
                viewModel.startWatchingOtherDevices() // the indicator; the phone stays as it is
                #endif
            }
            #if os(macOS)
            // A dictation started with the global shortcut goes back to the app it came from
            // once its text is on the clipboard; anything else leaves the target alone.
            .onChange(of: viewModel.phase) { _, phase in
                switch phase {
                case .done:
                    PasteBack.shared.offer()
                    // Straight into the text with a caret at the end: a rewrite is usually
                    // read and tweaked, not admired. Skipped while a paste-back is waiting,
                    // where Return belongs to the confirm bar rather than to the text.
                    if pasteBack.offeredAppName == nil, styledDraft == nil,
                       let styled = viewModel.styledText {
                        editorHeight = 0
                        styledDraft = styled
                        resultLabel = .idle
                    }
                case .idle, .error:
                    PasteBack.shared.disarm()
                    endEditing()
                case .recording, .transcribing, .rewriting:
                    // New text is on its way: stop editing the old, and make sure the
                    // pending copy cannot write the old draft over it.
                    endEditing()
                }
            }
            // A re-style, a restore from History or a dictation claimed from the phone all
            // replace the result while the card may still be holding the previous one.
            .onChange(of: viewModel.styledText) { _, styled in
                guard let styled, styledDraft != nil, styledDraft != styled else { return }
                copyAfterTyping?.cancel()
                editorHeight = 0
                styledDraft = styled
                resultLabel = .idle
            }
            #endif
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
            // How far the editor may grow before it starts scrolling inside itself: enough
            // room is kept below for the raw transcript, which stays readable while editing.
            .background {
                GeometryReader { geometry in
                    Color.clear.onChange(of: geometry.size.height, initial: true) { _, height in
                        editorCeiling = max(ResultTypography.lineHeight * 4, height - 180)
                    }
                }
            }
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
                    // Also the way to put it back on the clipboard, which is what you want
                    // right after editing it.
                    Button {
                        viewModel.copyStyledAgain()
                        flashCopied()
                    } label: {
                        // Not a Label: its three symbols are different widths, so the text
                        // shifted every time the state changed. A fixed box holds the line.
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            // The box fixes the layout in both directions: the three symbols
                            // differ in height as well as width, so a width-only frame still
                            // let the row grow and the text ride up and down with it.
                            Image(systemName: resultLabelIcon)
                                .frame(width: 15, height: 12, alignment: .center)
                            Text(resultLabelText)
                        }
                        .frame(height: 14, alignment: .center)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                        .animation(.easeInOut(duration: 0.15), value: resultLabelText)
                    }
                    .buttonStyle(.plain)
                    .help("Copy again")
                    .accessibilityLabel("Copy the result again")
                    Spacer()
                    if viewModel.selectedStyle.usesMarkdown {
                        markdownToggle
                    }
                }
                #if os(macOS)
                // Edited where it sits: clicking the card turns the rendered result into its
                // markdown source in the same frame, so it reads as putting a cursor in the
                // text rather than opening a screen.
                if styledDraft != nil {
                    MarkdownTextView(
                        text: Binding(get: { styledDraft ?? "" }, set: { styledDraft = $0 }),
                        onChange: { textView in
                            measureEditor(textView, deferred: false)
                            typedInResult()
                        },
                        onCommit: { commitStyledEdit() }
                    )
                    .frame(height: max(editorHeight, ResultTypography.lineHeight))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                } else {
                    MarkdownView(markdown: styled)
                }
                #else
                MarkdownView(markdown: styled)
                #endif
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
            // The card itself is the edit affordance. Applied inside the glass so the hover
            // tint sits between glass and text.
            .tapToEdit("Edit formatted text", shape: RoundedRectangle(cornerRadius: 16)) {
                #if os(macOS)
                editorHeight = 0
                styledDraft = styled
                #else
                editTarget = .styled
                #endif
            }
            // While editing the card is a solid sheet rather than glass, so the text view can
            // be opaque and repaint cleanly as it grows.
            .background {
                if isEditingResult {
                    RoundedRectangle(cornerRadius: 16).fill(Color.editorSurface)
                }
            }
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
                    Button {
                        viewModel.copyRaw()
                    } label: {
                        Label("Copy raw", systemImage: "doc.on.doc")
                            .font(.caption)
                    }
                    .compactActionStyle()
                    .accessibilityLabel("Copy raw transcript")
                }
                Text(raw)
                    .font(PlatformFont.rawTranscript)
                    // The rewrite is the result; the raw text is there to check it against,
                    // so it stays a glance rather than a wall. The editor shows all of it.
                    .lineLimit(viewModel.styledText == nil ? nil : 4)
                    .foregroundStyle(viewModel.styledText == nil ? .primary : .secondary)
            }
            .padding(.horizontal) // align with the styled card's inner content
            .padding(.vertical, 10) // air inside the hover tint …
            .tapToEdit("Edit raw transcript", shape: RoundedRectangle(cornerRadius: 12), tint: 0.03) {
                editTarget = .raw
            }
            .padding(.vertical, -10) // … without moving the block in the layout
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

    #if os(macOS)
    /// Drops the edit in progress, with nothing left to fire afterwards.
    private func endEditing() {
        copyAfterTyping?.cancel()
        copyAfterTyping = nil
        styledDraft = nil
        editorHeight = 0
        resultLabel = .idle
    }

    /// Clicking away finishes the edit.
    private func commitStyledEdit() {
        copyAfterTyping?.cancel()
        guard let draft = styledDraft else { return }
        styledDraft = nil
        if draft != viewModel.styledText {
            viewModel.applyStyledEdit(draft)
            flashCopied()
        }
    }

    /// Each keystroke says "Writing…" and restarts the three-second wait; when it elapses the
    /// text goes back on the clipboard and the label says so. No save button anywhere.
    private func typedInResult() {
        if resultLabel != .writing { resultLabel = .writing }
        copyAfterTyping?.cancel()
        copyAfterTyping = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, let draft = styledDraft else { return }
            if draft != viewModel.styledText { viewModel.applyStyledEdit(draft) }
            flashCopied()
        }
    }
    #endif

    #if os(macOS)
    /// The height the text actually needs, capped at what the window leaves and never
    /// falling back below what it already claimed during this edit.
    private func measureEditor(_ textView: NSTextView, deferred: Bool = true) {
        let width = textView.textContainer?.containerSize.width ?? textView.bounds.width
        guard width > 0 else { return }
        let used = textView.attributedString().boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]).height
        // Just the text, plus a couple of points so the last line is never clipped. A whole
        // line of slack here left an empty one sitting under the cursor.
        let wanted = min(ceil(used) + 2, max(editorCeiling, ResultTypography.lineHeight * 3))
        guard wanted > editorHeight + 0.5 else { return }
        if deferred {
            Task { @MainActor in editorHeight = wanted } // introspect runs inside a view update
        } else {
            editorHeight = wanted
        }
        textView.needsDisplay = true // the frame is about to change under it
    }
    #endif

    /// True only on the Mac, and only while the result is being typed into.
    private var isEditingResult: Bool {
        #if os(macOS)
        styledDraft != nil
        #else
        false
        #endif
    }

    /// Confirms a copy for a moment, then goes back to naming the style.
    private func flashCopied() {
        resultLabel = .copied
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            if resultLabel == .copied { resultLabel = .idle }
        }
    }

    private var resultLabelText: String {
        switch resultLabel {
        case .writing: "Writing…"
        case .copied: "Copied"
        // Not the style name: the highlighted pill below already says which one it is.
        case .idle: "Copied"
        }
    }

    private var resultLabelIcon: String {
        switch resultLabel {
        case .writing: "pencil"
        case .copied: "checkmark"
        case .idle: "doc.on.clipboard"
        }
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
                    .offset(x: -ControlMetrics.satelliteOffset)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .overlay(alignment: .trailing) {
            if viewModel.phase == .done, viewModel.rawTranscript != nil {
                continueButton
                    .offset(x: ControlMetrics.satelliteOffset)
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
            .font(.system(size: ControlMetrics.recordGlyph, weight: .semibold))
            .foregroundStyle(viewModel.recorder.isRecording ? Color.appBackground : .primary)
            .frame(width: ControlMetrics.record, height: ControlMetrics.record)
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
                .font(.system(size: ControlMetrics.satelliteGlyph, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: ControlMetrics.satellite, height: ControlMetrics.satellite)
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
                .font(.system(size: ControlMetrics.satelliteGlyph, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: ControlMetrics.satellite, height: ControlMetrics.satellite)
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
