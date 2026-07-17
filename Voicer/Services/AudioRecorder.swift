import AVFoundation
import Observation

/// Records microphone audio to a temp 16 kHz mono PCM .wav — Whisper's expected format
/// (plan Phase 2).
@Observable
@MainActor
final class AudioRecorder {
    private var recorder: AVAudioRecorder?
    private(set) var isRecording = false
    private(set) var startedAt: Date?

    func start() async throws {
        guard await AVAudioApplication.requestRecordPermission() else {
            throw AppError.microphonePermissionDenied
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voicer-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        guard recorder.record() else { throw AppError.recordingFailed }
        self.recorder = recorder
        isRecording = true
        startedAt = Date()
    }

    func stop() throws -> URL {
        guard let recorder else { throw AppError.recordingFailed }
        recorder.stop()
        let url = recorder.url
        self.recorder = nil
        isRecording = false
        startedAt = nil
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: .notifyOthersOnDeactivation)
        return url
    }

    /// Discards an in-flight recording without processing it.
    func cancel() {
        recorder?.stop()
        if let url = recorder?.url {
            try? FileManager.default.removeItem(at: url)
        }
        recorder = nil
        isRecording = false
        startedAt = nil
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: .notifyOthersOnDeactivation)
    }
}
