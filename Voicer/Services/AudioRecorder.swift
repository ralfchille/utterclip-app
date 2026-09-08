import AVFoundation
import Observation

/// One metered mic sample; the id keeps bar identity stable as the window slides,
/// so the waveform bars glide left instead of morphing in place.
struct LevelSample: Identifiable, Equatable {
    let id: Int
    let value: Float
}

/// Records microphone audio to a temp 16 kHz mono PCM .wav — Whisper's expected format
/// (plan Phase 2).
@Observable
@MainActor
final class AudioRecorder {
    private var recorder: AVAudioRecorder?
    private(set) var isRecording = false
    private(set) var startedAt: Date?

    /// Rolling window of normalized mic levels (0…1, newest last) for the live waveform.
    private(set) var levels: [LevelSample] = []
    private static let levelWindow = 40
    private var sampleCount = 0
    private var meterTask: Task<Void, Never>?

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
        recorder.isMeteringEnabled = true
        guard recorder.record() else { throw AppError.recordingFailed }
        self.recorder = recorder
        isRecording = true
        startedAt = Date()
        startMetering()
    }

    func stop() throws -> URL {
        guard let recorder else { throw AppError.recordingFailed }
        stopMetering()
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
        stopMetering()
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

    // MARK: - Metering

    private func startMetering() {
        levels = []
        sampleCount = 0
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.isRecording else { break }
                self.sampleLevel()
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func stopMetering() {
        meterTask?.cancel()
        meterTask = nil
        levels = []
    }

    private func sampleLevel() {
        guard let recorder else { return }
        recorder.updateMeters()
        let dB = recorder.averagePower(forChannel: 0) // -160…0 dBFS
        let normalized = max(0, min(1, (dB + 50) / 50))
        // Slight curve keeps room noise as dots while speech still fills the bar.
        let shaped = pow(normalized, 1.5)
        sampleCount += 1
        levels.append(LevelSample(id: sampleCount, value: shaped))
        if levels.count > Self.levelWindow {
            levels.removeFirst(levels.count - Self.levelWindow)
        }
    }
}
