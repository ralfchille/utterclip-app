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

    public private(set) var phase: Phase = .idle
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

    /// History entry the current dictation writes into; nil until a transcript exists.
    private var currentEntryID: UUID?

    /// Set while a recording should be appended to the transcript on screen instead of
    /// replacing it (see `continueRecording`).
    private var isContinuing = false

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
        didSet { UserDefaults.standard.set(copyAsMarkdown, forKey: Self.copyAsMarkdownKey) }
    }

    /// Swap emails, phone numbers, links and addresses for placeholders before a rewrite
    /// leaves the device, restoring them in the result (see `Redactor`). On by default.
    public var redactPersonalData: Bool {
        didSet { UserDefaults.standard.set(redactPersonalData, forKey: Self.redactPersonalDataKey) }
    }

    /// Rewrite with Apple's on-device model (`LocalRewriter`) instead of the cloud provider.
    /// The engines produce different text, so switching clears the per-style cache.
    public var useOnDeviceModel: Bool {
        didSet {
            UserDefaults.standard.set(useOnDeviceModel, forKey: Self.useOnDeviceModelKey)
            rewriteCache.removeAll()
        }
    }

    /// The device could run Apple's model (right OS, eligible hardware) — gates whether the
    /// on-device option appears at all. See `onDeviceAvailable` for "ready right now".
    public var onDeviceSupported: Bool { LocalRewriter.isSupported }
    public var onDeviceAvailable: Bool { LocalRewriter.isAvailable }
    public var onDeviceUnavailabilityReason: String? { LocalRewriter.unavailabilityReason }

    public var defaultStyleID: String {
        get {
            let stored = UserDefaults.standard.string(forKey: Self.defaultStyleKey) ?? Styles.defaultStyle.id
            // A saved default may name a style that no longer exists (a removed built-in id,
            // or a deleted user-added style) — fall back so the picker and the one-tap
            // rewrite stay consistent.
            if StyleStore.shared.styleIfPresent(withID: stored) != nil { return stored }
            return StyleStore.shared.styles.first?.id ?? Styles.defaultStyle.id
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.defaultStyleKey)
            // With nothing on screen the pills show the upcoming style; keep them in step with
            // the new default. A shown result keeps its own pill — the text belongs to it.
            if rawTranscript == nil {
                selectedStyle = StyleStore.shared.style(withID: newValue)
            }
        }
    }

    public init(cloudRewriter: Rewriter = CloudRewriter(keyProvider: { KeyProvider.shared.apiKey() })) {
        self.cloudRewriter = cloudRewriter
        self.copyAsMarkdown = UserDefaults.standard.bool(forKey: Self.copyAsMarkdownKey)
        self.redactPersonalData = UserDefaults.standard.object(forKey: Self.redactPersonalDataKey) as? Bool ?? true
        self.useOnDeviceModel = UserDefaults.standard.bool(forKey: Self.useOnDeviceModelKey)
        self.selectedStyle = Styles.defaultStyle // placeholder until `self` is fully initialized
        self.selectedStyle = StyleStore.shared.style(withID: defaultStyleID)
        // Hands-free finish: 5 s of silence after speech ends the recording as if the
        // stop button had been tapped (same haptic, same transcribe → rewrite flow).
        recorder.onSilence = { [weak self] in
            guard let self, self.phase == .recording else { return }
            self.stopAndProcess()
        }
    }

    public var isBusy: Bool {
        phase == .transcribing || phase == .rewriting
    }

    public func record() async {
        isContinuing = false
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

    /// Starts a history entry for a finished dictation. Blank transcripts are not logged.
    private func logDictation(_ raw: String) {
        currentEntryID = nil
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let entry = HistoryEntry(
            id: UUID(), date: .now, rawTranscript: raw, styledText: nil, styleID: nil)
        HistoryStore.shared.add(entry)
        currentEntryID = entry.id
    }

    private func updateCurrentEntry(_ mutate: (inout HistoryEntry) -> Void) {
        guard let id = currentEntryID else { return }
        HistoryStore.shared.update(id, mutate)
    }

    /// Brings a past dictation back as the current result and re-copies it in the
    /// current copy mode, so restoring behaves exactly like having just dictated it.
    public func restore(_ entry: HistoryEntry) {
        recorder.cancel()
        processingTask?.cancel()
        rawTranscript = entry.rawTranscript
        styledText = entry.styledText
        rewriteError = nil
        rewriteNeedsKey = false
        currentEntryID = entry.id
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

    /// Plain-text copy by default (markdown characters stripped); raw markdown when
    /// the markdown mode is active. Always a plain string — rich clipboard items broke
    /// pasting into single-line inputs on the Mac.
    private func copyStyled(_ text: String) {
        Clipboard.copy(copyAsMarkdown ? text : MarkdownStripper.plainText(text))
    }

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
