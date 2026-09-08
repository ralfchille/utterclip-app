import Foundation
import Observation
import WhisperKit
import os

/// Warm-loaded WhisperKit singleton (plan Phase 3).
///
/// The multilingual `small` model (Argmax's quantized `small_216MB` build, less than half
/// the download of the full-precision one at near-identical accuracy) is downloaded from
/// Hugging Face on first launch (delivery option A) and cached; on every launch it is loaded
/// into memory exactly once via `warmUp()` and kept resident so recordings never pay a
/// per-use load cost.
@Observable
@MainActor
public final class TranscriptionService {
    public static let shared = TranscriptionService()

    public enum State: Equatable {
        case cold, warming, ready
        case failed(String)
    }

    public private(set) var state: State = .cold
    private var whisperKit: WhisperKit?
    private let logger = Logger(subsystem: "com.ralfchille.utterclip", category: "transcription")

    /// The WhisperKit model variant in use; see `warmUp()`.
    static let modelVariant = "small_216MB"

    /// Model folders earlier builds downloaded and this one no longer uses. Deleted once the
    /// current model is ready so an upgrade doesn't leave ~500 MB of dead weight in Documents.
    private static let supersededModelVariants = ["openai_whisper-small"]

    private init() {}

    /// Housekeeping once the model is ready: drop models from earlier builds, and keep the
    /// cache out of iCloud/computer backups — it is ~220 MB of re-downloadable data.
    private static func tidyModelStorage() {
        // WhisperKit's default download base: Documents/huggingface/models/<repo>/<variant>.
        var downloadBase = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appending(path: "huggingface")
        let repoFolder = downloadBase.appending(path: "models/argmaxinc/whisperkit-coreml")
        for variant in supersededModelVariants {
            let folder = repoFolder.appending(path: variant)
            guard FileManager.default.fileExists(atPath: folder.path) else { continue }
            try? FileManager.default.removeItem(at: folder)
        }
        // The flag on the directory covers everything inside it.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? downloadBase.setResourceValues(values)
    }

    /// Idempotent: loads + compiles the model in a background task. Safe to call again
    /// after a failure to retry. Transient failures (e.g. the first-launch download
    /// losing network) are retried automatically before surfacing an error.
    public func warmUp() {
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
                    // Resolves to the multilingual openai_whisper-small_216MB folder in the
                    // whisperkit-coreml repo (the ".en" builds are English-only; the plain
                    // "small" is the same model at ~500 MB). Language is auto-detected, so
                    // German and English both work untoggled. prewarm forces CoreML/ANE
                    // specialization here at launch instead of on the user's first recording.
                    let config = WhisperKitConfig(model: Self.modelVariant, prewarm: true)
                    let kit = try await WhisperKit(config)
                    self.whisperKit = kit
                    self.state = .ready
                    Self.tidyModelStorage()
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

    public func transcribe(_ audioURL: URL) async throws -> String {
        // Recording may start before the model finishes loading — wait for the
        // in-flight warm-up so the load hides behind the recording time.
        while state == .cold || state == .warming {
            try await Task.sleep(for: .milliseconds(150))
        }
        guard case .ready = state, let kit = whisperKit else { throw AppError.modelNotReady }
        // Explicit auto-detection: without it the decoder prefills the English token
        // and German speech comes out (loosely) translated instead of transcribed.
        var options = DecodingOptions()
        options.task = .transcribe
        options.detectLanguage = true
        let start = ContinuousClock.now
        let results = try await kit.transcribe(audioPath: audioURL.path, decodeOptions: options)
        logger.info("Transcription took \(ContinuousClock.now - start, privacy: .public)")
        // Whisper marks non-speech audio with tokens like "[BLANK_AUDIO]" or "[MUSIC]";
        // they aren't dictation and must not reach the clipboard or history.
        let text = results.map(\.text).joined()
            .replacing(#/\[[A-Z_ ]+\]/#, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AppError.emptyTranscript }
        return text
    }
}
