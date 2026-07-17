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
        rawTranscript = nil
        styledText = nil
        rewriteError = nil
        do {
            try await recorder.start()
            phase = .recording
            haptic(.medium)
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    func stopAndProcess() async {
        haptic(.medium)
        do {
            let audioURL = try recorder.stop()
            phase = .transcribing
            let raw = try await transcription.transcribe(audioURL)
            rawTranscript = raw
            Clipboard.copy(raw) // fast path: raw text is pasteable before any network call
            try? FileManager.default.removeItem(at: audioURL)
            await rewrite(with: StyleStore.shared.style(withID: defaultStyleID))
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    /// Runs (or re-runs) the rewrite for a style and copies the result (plan Phase 6).
    func rewrite(with style: MessageStyle) async {
        guard let raw = rawTranscript else { return }
        // Re-fetch by id so a prompt edited in Settings applies to the next rewrite.
        let style = StyleStore.shared.style(withID: style.id)
        selectedStyle = style
        rewriteError = nil
        phase = .rewriting
        do {
            let styled = try await rewriter.rewrite(raw, style: style)
            styledText = styled
            copyStyled(styled)
        } catch {
            rewriteError = error.localizedDescription
        }
        phase = .done
    }

    /// Rich (HTML/RTF) copy by default so Google Docs/Mail/Word paste real formatting;
    /// raw markdown when the markdown mode is active.
    private func copyStyled(_ text: String) {
        if copyAsMarkdown {
            Clipboard.copy(text)
        } else {
            Clipboard.copyFormatted(text)
        }
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

    /// Recovers the raw transcript onto the clipboard in case the rewrite isn't wanted.
    func copyRaw() {
        guard let raw = rawTranscript else { return }
        Clipboard.copy(raw)
        haptic(.light)
    }

    func dismissError() {
        recorder.cancel()
        phase = rawTranscript == nil ? .idle : .done
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
