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
        self.selectedStyle = Styles.defaultStyle
        self.selectedStyle = Styles.style(withID: defaultStyleID)
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
            await rewrite(with: Styles.style(withID: defaultStyleID))
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    /// Runs (or re-runs) the rewrite for a style and copies the result (plan Phase 6).
    func rewrite(with style: MessageStyle) async {
        guard let raw = rawTranscript else { return }
        selectedStyle = style
        rewriteError = nil
        phase = .rewriting
        do {
            let styled = try await rewriter.rewrite(raw, style: style)
            styledText = styled
            Clipboard.copy(styled)
        } catch {
            rewriteError = error.localizedDescription
        }
        phase = .done
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
