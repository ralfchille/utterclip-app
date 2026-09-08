import Foundation
import Observation
import SwiftUI

/// Orchestrates the full flow (plan Phase 7):
/// record → stop → transcribe → copy raw immediately → rewrite with default style →
/// copy styled. Rewrite failures never block the fast path — the raw transcript is
/// already on the clipboard before the rewrite starts.
@Observable
@MainActor
final class RecorderViewModel {
    enum Phase: Equatable {
        case idle, recording, transcribing, rewriting, done
        case error(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var rawTranscript: String?
    private(set) var styledText: String?
    /// Non-fatal rewrite failure — raw transcript remains available and copied.
    private(set) var rewriteError: String?
    private(set) var selectedStyle: MessageStyle

    let recorder = AudioRecorder()
    let transcription = TranscriptionService.shared
    private let rewriter: Rewriter

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

    /// When on, copies put raw markdown on the clipboard instead of the rich
    /// (HTML/RTF) representations. Persists across recordings and launches.
    var copyAsMarkdown: Bool {
        didSet { UserDefaults.standard.set(copyAsMarkdown, forKey: Self.copyAsMarkdownKey) }
    }

    var defaultStyleID: String {
        get {
            UserDefaults.standard.string(forKey: Self.defaultStyleKey) ?? Styles.defaultStyle.id
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.defaultStyleKey)
        }
    }

    init(rewriter: Rewriter = CloudRewriter(keyProvider: { KeyProvider.shared.apiKey() })) {
        self.rewriter = rewriter
        self.copyAsMarkdown = UserDefaults.standard.bool(forKey: Self.copyAsMarkdownKey)
        self.selectedStyle = Styles.defaultStyle
        // A saved default may reference a removed style id (e.g. "structured") —
        // fall back to the app default so the Settings picker stays consistent.
        if !Styles.all.contains(where: { $0.id == defaultStyleID }) {
            defaultStyleID = Styles.defaultStyle.id
        }
        self.selectedStyle = StyleStore.shared.style(withID: defaultStyleID)
    }

    var isBusy: Bool {
        phase == .transcribing || phase == .rewriting
    }

    func record() async {
        isContinuing = false
        rawTranscript = nil
        styledText = nil
        rewriteError = nil
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
    func continueRecording() async {
        guard rawTranscript != nil else { return await record() }
        isContinuing = true
        rewriteError = nil
        do {
            try await recorder.start()
            phase = .recording
            haptic(.medium)
        } catch {
            isContinuing = false
            phase = .error(error.localizedDescription)
        }
    }

    func stopAndProcess() async {
        haptic(.medium)
        let appending = isContinuing
        isContinuing = false
        do {
            let audioURL = try recorder.stop()
            phase = .transcribing
            let chunk = try await transcription.transcribe(audioURL)
            try? FileManager.default.removeItem(at: audioURL)
            rewriteCache.removeAll() // the transcript changes below either way
            if appending, let base = rawTranscript {
                let combined = base + " " + chunk
                rawTranscript = combined
                styledText = nil // don't show the old rewrite against the longer transcript
                Clipboard.copy(combined)
                updateCurrentEntry { $0.rawTranscript = combined }
                await rewrite(with: selectedStyle)
            } else {
                rawTranscript = chunk
                Clipboard.copy(chunk) // fast path: raw text is pasteable before any network call
                logDictation(chunk)
                await rewrite(with: StyleStore.shared.style(withID: defaultStyleID))
            }
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    /// Runs (or re-runs) the rewrite for a style and copies the result (plan Phase 6).
    /// A style already rewritten for the current transcript is served from the cache —
    /// re-tapping a pill or switching back to one re-copies instantly, no network call.
    func rewrite(with style: MessageStyle) async {
        guard let raw = rawTranscript else { return }
        // Re-fetch by id so a prompt edited in Settings applies to the next rewrite.
        let style = StyleStore.shared.style(withID: style.id)
        selectedStyle = style
        rewriteError = nil
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
            let styled = try await rewriter.rewrite(raw, style: style)
            rewriteCache[style] = styled
            styledText = styled
            copyStyled(styled)
            updateCurrentEntry { entry in
                entry.styledText = styled
                entry.styleID = style.id
            }
        } catch {
            rewriteError = error.localizedDescription
        }
        phase = .done
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
    func restore(_ entry: HistoryEntry) {
        recorder.cancel()
        rawTranscript = entry.rawTranscript
        styledText = entry.styledText
        rewriteError = nil
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
    func toggleMarkdownCopy() {
        copyAsMarkdown.toggle()
        if let styled = styledText {
            copyStyled(styled)
        }
        haptic(.light)
    }

    /// Applies a user-edited version of the styled result and re-copies it in the
    /// current copy mode. Empty edits are ignored so a stray clear can't wipe the
    /// result out from under the copy that's already on the clipboard.
    func applyStyledEdit(_ edited: String) {
        let trimmed = edited.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        styledText = trimmed
        copyStyled(trimmed)
        rewriteCache[selectedStyle] = trimmed // keep the edit when switching pills and back
        updateCurrentEntry { $0.styledText = trimmed }
        successHaptic()
    }

    /// Applies a user-edited raw transcript and copies it as plain text.
    func applyRawEdit(_ edited: String) {
        let trimmed = edited.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        rawTranscript = trimmed
        Clipboard.copy(trimmed)
        rewriteCache.removeAll() // styled versions no longer match the transcript
        updateCurrentEntry { $0.rawTranscript = trimmed }
        successHaptic()
    }

    /// Recovers the raw transcript onto the clipboard in case the rewrite isn't wanted.
    func copyRaw() {
        guard let raw = rawTranscript else { return }
        Clipboard.copy(raw)
        haptic(.light)
    }

    /// Discards the in-flight recording without transcribing or copying anything.
    func cancelRecording() {
        recorder.cancel()
        isContinuing = false // an abandoned continuation leaves the transcript untouched
        phase = rawTranscript == nil ? .idle : .done
        haptic(.light)
    }

    func dismissError() {
        recorder.cancel()
        phase = rawTranscript == nil ? .idle : .done
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    /// The system "done" pattern for a completed save — clearer than an impact tap,
    /// which is easy to miss while the editor is dismissing.
    private func successHaptic() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
