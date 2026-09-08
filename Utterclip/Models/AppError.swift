import Foundation

/// Shared error type used across services (plan Phase 1, step 5).
enum AppError: LocalizedError {
    case microphonePermissionDenied
    case recordingFailed
    case modelNotReady
    case transcriptionFailed(String)
    case emptyTranscript
    case noApiKey
    case rewriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access is denied. Enable it in Settings → Privacy → Microphone."
        case .recordingFailed:
            return "Recording failed. Please try again."
        case .modelNotReady:
            return "The transcription model isn't ready yet. Give it a moment and try again."
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        case .emptyTranscript:
            return "Nothing was transcribed — the recording may have been silent or too short."
        case .noApiKey:
            return "No API key set. Add your Anthropic API key in Settings."
        case .rewriteFailed(let message):
            return "Rewrite failed: \(message)"
        }
    }
}
