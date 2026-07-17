import Foundation
import Observation
import WhisperKit
import os

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
    private let logger = Logger(subsystem: "com.babbellabs.voicer", category: "transcription")

    private init() {}

    /// Idempotent: loads + compiles the model in a background task. Safe to call again
    /// after a failure to retry. Transient failures (e.g. the first-launch download
    /// losing network) are retried automatically before surfacing an error.
    func warmUp() {
        switch state {
        case .warming, .ready: return
        case .cold, .failed: break
        }
        state = .warming
        Task {
            var lastError: Error?
            for attempt in 1...3 {
                do {
                    let start = ContinuousClock.now
                    // "small" resolves to the multilingual openai_whisper-small variant;
                    // language is auto-detected, so German and English both work untoggled.
                    // prewarm forces CoreML/ANE specialization here at launch instead of
                    // on the user's first recording.
                    let config = WhisperKitConfig(model: "small", prewarm: true)
                    let kit = try await WhisperKit(config)
                    self.whisperKit = kit
                    self.state = .ready
                    logger.info("Whisper model ready in \(ContinuousClock.now - start, privacy: .public) (attempt \(attempt))")
                    return
                } catch {
                    lastError = error
                    logger.error("Warm-up attempt \(attempt) failed: \(String(describing: error))")
                    try? await Task.sleep(for: .seconds(2))
                }
            }
            // String(describing:) keeps WhisperKit's error detail that
            // localizedDescription often drops.
            self.state = .failed(lastError.map { String(describing: $0) } ?? "Unknown error")
        }
    }

    func transcribe(_ audioURL: URL) async throws -> String {
        guard let kit = whisperKit else { throw AppError.modelNotReady }
        // Explicit auto-detection: without it the decoder prefills the English token
        // and German speech comes out (loosely) translated instead of transcribed.
        var options = DecodingOptions()
        options.task = .transcribe
        options.detectLanguage = true
        let start = ContinuousClock.now
        let results = try await kit.transcribe(audioPath: audioURL.path, decodeOptions: options)
        logger.info("Transcription took \(ContinuousClock.now - start, privacy: .public)")
        let text = results.map(\.text).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AppError.emptyTranscript }
        return text
    }
}
