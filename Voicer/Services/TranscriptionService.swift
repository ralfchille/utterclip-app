import Foundation
import Observation
import WhisperKit

/// Warm-loaded WhisperKit singleton (plan Phase 3).
///
/// The multilingual `small` model is downloaded from Hugging Face on first launch
/// (delivery option A) and cached; on every launch it is loaded into memory exactly once
/// via `warmUp()` and kept resident so recordings never pay a per-use load cost.
@Observable
@MainActor
final class TranscriptionService {
    static let shared = TranscriptionService()

    enum State: Equatable {
        case cold, warming, ready
        case failed(String)
    }

    private(set) var state: State = .cold
    private var whisperKit: WhisperKit?

    private init() {}

    /// Idempotent: loads + compiles the model in a background task. Safe to call again
    /// after a failure to retry.
    func warmUp() {
        switch state {
        case .warming, .ready: return
        case .cold, .failed: break
        }
        state = .warming
        Task {
            do {
                // "small" resolves to the multilingual openai_whisper-small variant;
                // language is auto-detected, so German and English both work untoggled.
                let config = WhisperKitConfig(model: "small")
                let kit = try await WhisperKit(config)
                self.whisperKit = kit
                self.state = .ready
            } catch {
                self.state = .failed(error.localizedDescription)
            }
        }
    }

    func transcribe(_ audioURL: URL) async throws -> String {
        guard let kit = whisperKit else { throw AppError.modelNotReady }
        let results = try await kit.transcribe(audioPath: audioURL.path)
        let text = results.map(\.text).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AppError.emptyTranscript }
        return text
    }
}
