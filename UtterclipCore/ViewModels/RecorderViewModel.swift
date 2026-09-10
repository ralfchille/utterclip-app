import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// Orchestrates the full flow (plan Phase 7):
/// record → stop → transcribe → copy raw immediately → rewrite with default style →
/// copy styled. Rewrite failures never block the fast path — the raw transcript is
/// already on the clipboard before the rewrite starts.
@Observable
@MainActor
public final class RecorderViewModel {
    public enum Phase: Equatable {
        case idle, recording, transcribing, rewriting, done
        case error(String)
    }

    public private(set) var phase: Phase = .idle {
        didSet { phaseDidChange() }
    }
    public private(set) var rawTranscript: String?
    public private(set) var styledText: String?
    /// Non-fatal rewrite failure — raw transcript remains available and copied.
    public private(set) var rewriteError: String?
    /// The rewrite couldn't run for lack of a working API key; the UI points to Settings.
    public private(set) var rewriteNeedsKey = false
    /// Non-error status after a recording with no speech (Whisper's "[BLANK_AUDIO]");
    /// nothing is copied or logged in that case. Cleared by the next recording.
    public private(set) var notice: String?
    /// The highlighted pill: the style the current result was rewritten in, and the one the
    /// next recording will be rewritten in. Starts at the Settings default on launch.
    public private(set) var selectedStyle: MessageStyle

    public let recorder = AudioRecorder()
    public let transcription = TranscriptionService.shared
    private let cloudRewriter: Rewriter
    private let localRewriter: Rewriter = LocalRewriter()

    /// The transcribe/rewrite job in flight, so the ✕ beside the mic can abandon it.
    private var processingTask: Task<Void, Never>?
    /// Pill highlighted before a rewrite started; restored if that rewrite is cancelled.
    private var styleBeforeRewrite: MessageStyle?

    /// The dictation on screen as it will be (or is) stored. Created when a transcript
    /// arrives, written to the store once the dictation has settled — rewrite finished,
    /// failed or abandoned — so other devices sync one finished entry instead of every
    /// intermediate state. Later edits update the stored entry directly.
    private var currentEntry: HistoryEntry?
    private var currentEntryIsStored = false

    /// Set while a recording should be appended to the transcript on screen instead of
    /// replacing it (see `continueRecording`).
    private var isContinuing = false

    // Mirroring another device (Mac only; see `startMirroring`).

    /// A dictation in progress on another device, shown here while this one is not busy.
    public private(set) var remoteActivity: ActivitySync.Remote?
    /// "iPhone" when the result on screen was dictated on another device and mirrored here.
    public private(set) var mirroredFrom: String?
    private var mirrorObserver: NSObjectProtocol?
    private var mirrorStartedAt = Date()
    private var lastMirroredDate = Date.distantPast
    private var pendingMirroredCopy = false
    private var isReconcilingRemote = false

    /// Rewrites already produced for the current transcript, keyed by the exact style
    /// (id + prompt) that produced them. Cleared whenever the transcript changes.
    private var rewriteCache: [MessageStyle: String] = [:]

    private static let defaultStyleKey = "defaultStyleID"
    private static let copyAsMarkdownKey = "copyAsMarkdown"
    private static let redactPersonalDataKey = "redactPersonalData"
    private static let useOnDeviceModelKey = "useOnDeviceModel"

    /// When on, copies put the raw markdown source on the clipboard instead of the
    /// stripped plain text. Persists across recordings and launches.
    public var copyAsMarkdown: Bool {
        didSet { if !isApplyingRemoteSettings { defaults.set(copyAsMarkdown, forKey: Self.copyAsMarkdownKey) } }
    }

    /// Swap emails, phone numbers, links and addresses for placeholders before a rewrite
    /// leaves the device, restoring them in the result (see `Redactor`). On by default.
    public var redactPersonalData: Bool {
        didSet { if !isApplyingRemoteSettings { defaults.set(redactPersonalData, forKey: Self.redactPersonalDataKey) } }
    }

    /// Rewrite with Apple's on-device model (`LocalRewriter`) instead of the cloud provider.
    /// The engines produce different text, so switching clears the per-style cache.
    public var useOnDeviceModel: Bool {
        didSet {
            // Deliberately per device (not synced): whether Apple's model is available differs
            // between a Mac and an iPhone, and between iPhones.
            UserDefaults.standard.set(useOnDeviceModel, forKey: Self.useOnDeviceModelKey)
            rewriteCache.removeAll()
        }
    }

    /// Settings and styles that follow the user through iCloud (see `SyncedDefaults`).
    private let defaults = SyncedDefaults.shared
    /// Set while another device's values are copied in, so the `didSet`s don't write them back.
    private var isApplyingRemoteSettings = false
    private var remoteSettingsObserver: NSObjectProtocol?

    /// The device could run Apple's model (right OS, eligible hardware) — gates whether the
    /// on-device option appears at all. See `onDeviceAvailable` for "ready right now".
    public var onDeviceSupported: Bool { LocalRewriter.isSupported }
    public var onDeviceAvailable: Bool { LocalRewriter.isAvailable }
    public var onDeviceUnavailabilityReason: String? { LocalRewriter.unavailabilityReason }

    public var defaultStyleID: String {
        get {
            let stored = defaults.string(forKey: Self.defaultStyleKey) ?? Styles.defaultStyle.id
            // A saved default may name a style that no longer exists (a removed built-in id,
            // or a deleted user-added style) — fall back so the picker and the one-tap
            // rewrite stay consistent.
            if StyleStore.shared.styleIfPresent(withID: stored) != nil { return stored }
            return StyleStore.shared.styles.first?.id ?? Styles.defaultStyle.id
        }
        set {
            defaults.set(newValue, forKey: Self.defaultStyleKey)
            // With nothing on screen the pills show the upcoming style; keep them in step with
            // the new default. A shown result keeps its own pill — the text belongs to it.
            if rawTranscript == nil {
                selectedStyle = StyleStore.shared.style(withID: newValue)
            }
        }
    }

    public init(cloudRewriter: Rewriter = CloudRewriter(keyProvider: { KeyProvider.shared.apiKey() })) {
        self.cloudRewriter = cloudRewriter
        self.copyAsMarkdown = SyncedDefaults.shared.bool(forKey: Self.copyAsMarkdownKey)
        self.redactPersonalData = SyncedDefaults.shared.object(forKey: Self.redactPersonalDataKey) as? Bool ?? true
        self.useOnDeviceModel = UserDefaults.standard.bool(forKey: Self.useOnDeviceModelKey)
        self.selectedStyle = Styles.defaultStyle // placeholder until `self` is fully initialized
        self.selectedStyle = StyleStore.shared.style(withID: defaultStyleID)
        // Hands-free finish: 5 s of silence after speech ends the recording as if the
        // stop button had been tapped (same haptic, same transcribe → rewrite flow).
        recorder.onSilence = { [weak self] in
            guard let self, self.phase == .recording else { return }
            self.stopAndProcess()
        }
        remoteSettingsObserver = NotificationCenter.default.addObserver(
            forName: SyncedDefaults.didChangeRemotely, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.applyRemoteSettings() }
        }
    }

    /// Another device changed a synced setting: take the new values without echoing them
    /// back, and keep the pill in step with the default while nothing is on screen.
    private func applyRemoteSettings() {
        isApplyingRemoteSettings = true
        defer { isApplyingRemoteSettings = false }
        copyAsMarkdown = defaults.bool(forKey: Self.copyAsMarkdownKey)
        redactPersonalData = defaults.object(forKey: Self.redactPersonalDataKey) as? Bool ?? true
        if rawTranscript == nil {
            selectedStyle = StyleStore.shared.style(withID: defaultStyleID)
        } else if StyleStore.shared.styleIfPresent(withID: selectedStyle.id) == nil {
            selectedStyle = StyleStore.shared.style(withID: defaultStyleID) // the pill was deleted elsewhere
        }
    }

    public var isBusy: Bool {
        phase == .transcribing || phase == .rewriting
    }

    public func record() async {
        isContinuing = false
        mirroredFrom = nil
        rawTranscript = nil
        styledText = nil
        rewriteError = nil
        rewriteNeedsKey = false
        notice = nil
        rewriteCache.removeAll()
        do {
            try await recorder.start()
            phase = .recording
            haptic(.medium)
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    /// Starts a recording that extends the transcript on screen instead of replacing it:
    /// the new speech is appended, the current style re-runs on the whole text, and the
    /// existing history entry grows rather than a new one being created.
    public func continueRecording() async {
        guard rawTranscript != nil else { return await record() }
        isContinuing = true
        rewriteError = nil
        rewriteNeedsKey = false
        notice = nil
        do {
            try await recorder.start()
            phase = .recording
            haptic(.medium)
        } catch {
            isContinuing = false
            phase = .error(error.localizedDescription)
        }
    }

    /// Stops the recording and runs transcribe → copy → rewrite as one cancellable job.
    public func stopAndProcess() {
        haptic(.medium)
        let appending = isContinuing
        isContinuing = false
        processingTask = Task { await performStopAndProcess(appending: appending) }
    }

    private func performStopAndProcess(appending: Bool) async {
        do {
            let audioURL = try recorder.stop()
            defer { try? FileManager.default.removeItem(at: audioURL) }
            phase = .transcribing
            let chunk = try await transcription.transcribe(audioURL)
            try Task.checkCancellation() // a late result must not overwrite a cancelled state
            rewriteCache.removeAll() // the transcript changes below either way
            if appending, let base = rawTranscript {
                let combined = base + " " + chunk
                rawTranscript = combined
                styledText = nil // don't show the old rewrite against the longer transcript
                Clipboard.copy(combined)
                updateCurrentEntry { $0.rawTranscript = combined }
                await performRewrite(with: selectedStyle)
            } else {
                rawTranscript = chunk
                Clipboard.copy(chunk) // fast path: raw text is pasteable before any network call
                logDictation(chunk)
                await performRewrite(with: selectedStyle) // the pill chosen before recording
            }
        } catch is CancellationError {
            // `cancel()` already restored the visible state.
        } catch AppError.emptyTranscript {
            // Silence or non-speech only: keep what was on screen, copy and log nothing.
            notice = "Nothing heard — tap the mic and try again."
            phase = rawTranscript == nil ? .idle : .done
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    /// A pill was tapped. With a transcript on screen that re-runs the rewrite; before any
    /// recording it just picks the style the upcoming recording will be rewritten in.
    public func select(_ style: MessageStyle) {
        if rawTranscript != nil {
            rewrite(with: style)
        } else {
            selectedStyle = StyleStore.shared.style(withID: style.id)
            haptic(.light)
        }
    }

    /// Runs (or re-runs) the rewrite for a style as a cancellable job (plan Phase 6).
    /// A style already rewritten for the current transcript is served from the cache —
    /// re-tapping a pill or switching back to one re-copies instantly, no network call.
    public func rewrite(with style: MessageStyle) {
        processingTask = Task { await performRewrite(with: style) }
    }

    private func performRewrite(with style: MessageStyle) async {
        guard let raw = rawTranscript else { return }
        // Whatever happens below — result, missing key, error, cancellation — the dictation
        // has settled once this attempt is over; that is when it goes into History.
        defer { commitCurrentEntry() }
        // Re-fetch by id so a prompt edited in Settings applies to the next rewrite.
        let style = StyleStore.shared.style(withID: style.id)
        styleBeforeRewrite = selectedStyle
        selectedStyle = style
        rewriteError = nil
        rewriteNeedsKey = false
        if let cached = rewriteCache[style] {
            styledText = cached
            copyStyled(cached)
            updateCurrentEntry { entry in
                entry.styledText = cached
                entry.styleID = style.id
            }
            phase = .done
            haptic(.light)
            return
        }
        phase = .rewriting
        do {
            // A stored on-device preference on a device that can't run the model (restored
            // backup, older phone) falls back to the cloud — the option is hidden there, so
            // the user couldn't switch it off themselves.
            let usingLocal = useOnDeviceModel && onDeviceSupported
            // Cloud only: personal identifiers leave the device as placeholders and come back
            // restored; the cache and history only ever hold the restored text. The on-device
            // model needs no redaction — nothing leaves the phone.
            let engine: Rewriter = usingLocal ? localRewriter : cloudRewriter
            let redaction = (redactPersonalData && !usingLocal) ? Redactor.redact(raw) : nil
            var styled = try await engine.rewrite(redaction?.text ?? raw, style: style)
            try Task.checkCancellation() // a late result must not overwrite a cancelled state
            if let redaction { styled = Redactor.restore(styled, redaction) }
            rewriteCache[style] = styled
            styledText = styled
            copyStyled(styled)
            updateCurrentEntry { entry in
                entry.styledText = styled
                entry.styleID = style.id
            }
        } catch is CancellationError {
            return // `cancel()` already restored the visible state.
        } catch AppError.noApiKey {
            rewriteNeedsKey = true // the UI points to Settings instead of offering a retry
        } catch {
            rewriteError = error.localizedDescription
        }
        phase = .done
    }

    /// Chosen from the missing-key card: switch engines and rewrite the current transcript.
    public func switchToOnDeviceModel() {
        useOnDeviceModel = true
        rewrite(with: selectedStyle)
    }

    // MARK: - History

    /// Starts the history entry for a finished dictation (in memory until it settles).
    /// Blank transcripts are not logged.
    private func logDictation(_ raw: String) {
        currentEntry = nil
        currentEntryIsStored = false
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        currentEntry = HistoryEntry(
            id: UUID(), date: .now, rawTranscript: raw, styledText: nil, styleID: nil,
            originDevice: DeviceIdentity.id)
    }

    private func updateCurrentEntry(_ mutate: (inout HistoryEntry) -> Void) {
        guard var entry = currentEntry else { return }
        mutate(&entry)
        currentEntry = entry
        if currentEntryIsStored {
            HistoryStore.shared.update(entry.id) { $0 = entry }
        }
    }

    /// Writes the pending entry to the store, once. Called when a rewrite attempt ends,
    /// whatever its outcome; a no-op for entries that are already stored.
    private func commitCurrentEntry() {
        guard let entry = currentEntry, !currentEntryIsStored else { return }
        HistoryStore.shared.add(entry)
        currentEntryIsStored = true
    }

    /// Brings a past dictation back as the current result and re-copies it in the
    /// current copy mode, so restoring behaves exactly like having just dictated it.
    public func restore(_ entry: HistoryEntry) {
        recorder.cancel()
        processingTask?.cancel()
        mirroredFrom = nil
        rawTranscript = entry.rawTranscript
        styledText = entry.styledText
        rewriteError = nil
        rewriteNeedsKey = false
        currentEntry = entry
        currentEntryIsStored = true
        rewriteCache.removeAll()
        if let styleID = entry.styleID {
            selectedStyle = StyleStore.shared.style(withID: styleID)
            // The entry's own result counts as already generated for its style.
            if let styled = entry.styledText { rewriteCache[selectedStyle] = styled }
        }
        if let styled = entry.styledText {
            copyStyled(styled)
        } else {
            Clipboard.copy(entry.rawTranscript)
        }
        phase = .done
        haptic(.light)
    }

    /// Plain-text copy by default (markdown characters stripped); raw markdown when the
    /// style keeps Markdown and the markdown mode is active. Always a plain string — rich
    /// clipboard items broke pasting into single-line inputs on the Mac.
    private func copyStyled(_ text: String) {
        Clipboard.copy(copiesMarkdown ? text : MarkdownStripper.plainText(text))
    }

    /// The Markdown switch is offered per style; for every other style results are plain.
    public var copiesMarkdown: Bool { selectedStyle.usesMarkdown && copyAsMarkdown }

    /// Toggles markdown-copy mode and immediately re-copies the current result in the
    /// new mode. The mode sticks until toggled off.
    public func toggleMarkdownCopy() {
        copyAsMarkdown.toggle()
        if let styled = styledText {
            copyStyled(styled)
        }
        haptic(.light)
    }

    /// Applies a user-edited version of the styled result and re-copies it in the
    /// current copy mode. Empty edits are ignored so a stray clear can't wipe the
    /// result out from under the copy that's already on the clipboard.
    public func applyStyledEdit(_ edited: String) {
        let trimmed = edited.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        styledText = trimmed
        copyStyled(trimmed)
        rewriteCache[selectedStyle] = trimmed // keep the edit when switching pills and back
        updateCurrentEntry { $0.styledText = trimmed }
        successHaptic()
    }

    /// Applies a user-edited raw transcript the same way a fresh recording lands: the
    /// plain text is copied right away, then the current style re-runs on it so the styled
    /// result (and its history entry) never lags behind the transcript. Saving the text
    /// unchanged leaves everything — including the clipboard — as it was.
    public func applyRawEdit(_ edited: String) {
        let trimmed = edited.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard trimmed != rawTranscript else { successHaptic(); return }
        rawTranscript = trimmed
        styledText = nil // the old rewrite no longer matches; the re-run below replaces it
        Clipboard.copy(trimmed) // fast path, pasteable before the rewrite finishes
        rewriteCache.removeAll() // styled versions no longer match the transcript
        updateCurrentEntry { entry in
            entry.rawTranscript = trimmed
            entry.styledText = nil // don't keep a rewrite of text that no longer exists
        }
        successHaptic()
        rewrite(with: selectedStyle)
    }

    /// Recovers the raw transcript onto the clipboard in case the rewrite isn't wanted.
    public func copyRaw() {
        guard let raw = rawTranscript else { return }
        Clipboard.copy(raw)
        haptic(.light)
    }

    /// The ✕ beside the mic: discards an in-flight recording, or abandons a transcription
    /// or rewrite in progress and returns to what was on screen before it started.
    public func cancel() {
        if recorder.isRecording {
            recorder.cancel()
        } else if isBusy {
            processingTask?.cancel()
            processingTask = nil
            if phase == .rewriting, let previous = styleBeforeRewrite {
                selectedStyle = previous // the result still on screen belongs to that pill
            }
            rewriteError = nil
        } else {
            return
        }
        isContinuing = false // an abandoned continuation leaves the transcript untouched
        phase = rawTranscript == nil ? .idle : .done
        haptic(.light)
    }

    public func dismissError() {
        recorder.cancel()
        phase = rawTranscript == nil ? .idle : .done
    }

    // MARK: - Mirroring another device

    /// Every phase change is published to the synced store, so the other devices can show
    /// what this one is doing. `done` carries the dictation's id.
    private func phaseDidChange() {
        let name: String
        switch phase {
        case .idle, .error: name = "idle"
        case .recording: name = "recording"
        case .transcribing: name = "transcribing"
        case .rewriting: name = "rewriting"
        case .done: name = "done"
        }
        // A mirrored result is the other device's news, not ours to re-announce.
        if !(phase == .done && mirroredFrom != nil) {
            ActivitySync.publish(phase: name, dictationID: phase == .done ? currentEntry?.id : nil)
        }
        // Our own work just ended: the other device may have moved on in the meantime.
        if mirrorObserver != nil, phase == .idle || phase == .done { reconcileRemoteActivity() }
    }

    /// Mac: follow the other devices. While this one is idle (or showing a result), a
    /// dictation happening on the phone appears here — "Recording on iPhone…", then the
    /// finished result, which is copied to this Mac's clipboard as soon as the window is
    /// visible. Nothing on the phone changes; it only publishes what it already syncs.
    public func startMirroring() {
        guard mirrorObserver == nil else { return }
        mirrorStartedAt = .now
        mirrorObserver = NotificationCenter.default.addObserver(
            forName: CloudStore.didChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reconcileRemoteActivity() }
        }
        reconcileRemoteActivity()
    }

    private func reconcileRemoteActivity() {
        guard !isReconcilingRemote, !recorder.isRecording, !isBusy else { return }
        isReconcilingRemote = true
        defer { isReconcilingRemote = false }
        HistoryStore.shared.reload() // the history observer may run after this one

        // 1. The mirrored result was edited or re-styled over there: follow it.
        if mirroredFrom != nil, let current = currentEntry,
           let updated = HistoryStore.shared.entry(id: current.id), updated != current {
            mirror(updated)
            return
        }
        // 2. A newer dictation finished elsewhere. Only ones from the last few minutes at
        //    launch — yesterday's phone result is History, not the current state.
        let floor = max(mirrorStartedAt.addingTimeInterval(-10 * 60), lastMirroredDate)
        if let entry = ActivitySync.latestRemoteDictation(after: floor),
           entry.id != currentEntry?.id,
           entry.date > (currentEntry?.date ?? .distantPast) {
            mirror(entry)
            return
        }
        // 3. Something in progress elsewhere (or nothing any more).
        if let remote = ActivitySync.latestRemote(), remote.isInProgress {
            remoteActivity = remote
        } else {
            remoteActivity = nil
        }
    }

    /// Shows another device's finished dictation as the result here, exactly as if it had
    /// been dictated on this device, and copies it — now, or when the window next appears.
    private func mirror(_ entry: HistoryEntry) {
        remoteActivity = nil
        rawTranscript = entry.rawTranscript
        styledText = entry.styledText
        rewriteError = nil
        rewriteNeedsKey = false
        notice = nil
        currentEntry = entry
        currentEntryIsStored = true
        rewriteCache.removeAll()
        if let styleID = entry.styleID {
            selectedStyle = StyleStore.shared.style(withID: styleID)
            if let styled = entry.styledText { rewriteCache[selectedStyle] = styled }
        }
        mirroredFrom = entry.originDevice.flatMap(ActivitySync.deviceName(for:)) ?? "iPhone"
        lastMirroredDate = max(lastMirroredDate, entry.date)
        phase = .done
        if WindowPresence.isVisible {
            copyMirroredResult()
        } else {
            pendingMirroredCopy = true
            WindowPresence.hasUnseenMirroredResult = true
        }
    }

    /// The window came on screen: a mirrored result that was waiting is copied now.
    public func windowDidShow() {
        WindowPresence.hasUnseenMirroredResult = false
        if pendingMirroredCopy { copyMirroredResult() }
    }

    private func copyMirroredResult() {
        pendingMirroredCopy = false
        if let styled = styledText {
            copyStyled(styled)
        } else if let raw = rawTranscript {
            Clipboard.copy(raw)
        }
    }

    // MARK: - Haptics

    /// Tap strengths used around the flow. UIKit's generators on iOS; silent on macOS,
    /// where a Mac app can opt into trackpad feedback (`NSHapticFeedbackManager`) itself.
    private enum Haptic { case light, medium }

    private func haptic(_ strength: Haptic) {
        #if canImport(UIKit)
        let style: UIImpactFeedbackGenerator.FeedbackStyle = strength == .light ? .light : .medium
        UIImpactFeedbackGenerator(style: style).impactOccurred()
        #endif
    }

    /// The system "done" pattern for a completed save — clearer than an impact tap,
    /// which is easy to miss while the editor is dismissing.
    private func successHaptic() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}
