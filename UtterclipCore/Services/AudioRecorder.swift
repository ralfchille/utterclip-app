import AVFoundation
import Observation

/// One metered mic sample; the id keeps bar identity stable as the window slides,
/// so the waveform bars glide left instead of morphing in place.
public struct LevelSample: Identifiable, Equatable {
    public let id: Int
    public let value: Float
}

/// Records microphone audio to a temp 16 kHz mono PCM .wav — Whisper's expected format
/// (plan Phase 2). Runs on iOS and macOS; only the audio-session handling is iOS-specific.
@Observable
@MainActor
public final class AudioRecorder {
    private var recorder: AVAudioRecorder?
    public private(set) var isRecording = false
    public private(set) var startedAt: Date?

    /// Rolling window of normalized mic levels (0…1, newest last) for the live waveform.
    public private(set) var levels: [LevelSample] = []
    private static let levelWindow = 40
    private var sampleCount = 0
    private var meterTask: Task<Void, Never>?

    /// Called once when the speaker has gone quiet for `silenceTimeout` — the owner
    /// decides what to do (the view model stops and transcribes). Only fires after some
    /// speech was heard, so someone gathering their thoughts isn't cut off before starting.
    @ObservationIgnored var onSilence: (@MainActor () -> Void)?
    private static let silenceTimeout: TimeInterval = 5
    /// Average level (dBFS) above which a metering sample counts as speech. Quiet-room
    /// noise on an iPhone sits around −50; normal speech peaks well above −30.
    private static let speechThresholdDB: Float = -40
    private var lastSpeechAt: Date?

    func start() async throws {
        guard await AVAudioApplication.requestRecordPermission() else {
            throw AppError.microphonePermissionDenied
        }

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)
        #endif

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("utterclip-\(UUID().uuidString).wav")
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
        deactivateSession()
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
        deactivateSession()
    }

    /// Hands the audio hardware back. `AVAudioSession` is iOS-only; macOS records without one.
    private func deactivateSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    // MARK: - Metering

    private func startMetering() {
        levels = []
        sampleCount = 0
        lastSpeechAt = nil
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
        trackSilence(dB)
    }

    /// Auto-stop: any sample above the speech threshold restarts the 5 s clock; once it
    /// runs out the handler fires a single time (clearing the mark prevents a repeat until
    /// speech resumes).
    private func trackSilence(_ dB: Float) {
        let now = Date()
        if dB > Self.speechThresholdDB {
            lastSpeechAt = now
        } else if let last = lastSpeechAt, now.timeIntervalSince(last) >= Self.silenceTimeout {
            lastSpeechAt = nil
            onSilence?()
        }
    }
}
