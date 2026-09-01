import Foundation
import AVFoundation

/// Wraps AVFoundation's `AVAudioRecorder` to capture microphone audio to a
/// file. This class only knows about recording start/stop and asking for
/// microphone permission -- it knows nothing about transcription or
/// summaries, which keeps it simple and easy to reuse.
@MainActor
final class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    /// Set to true if the user denies the microphone permission prompt, so
    /// the UI can show a helpful message instead of silently doing nothing.
    @Published var permissionDenied = false

    private var recorder: AVAudioRecorder?
    private(set) var currentFileURL: URL?

    /// Asks the user for microphone access (macOS only asks once; after that
    /// it remembers the choice in System Settings > Privacy & Security), then
    /// starts recording to a new file inside `directory`.
    ///
    /// We record directly at 16kHz mono, which is the format Whisper models
    /// are trained on -- recording in this format avoids an extra conversion
    /// step before transcription.
    func startRecording(into directory: URL, fileName: String) {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                guard granted else {
                    self.permissionDenied = true
                    return
                }
                self.beginRecording(into: directory, fileName: fileName)
            }
        }
    }

    private func beginRecording(into directory: URL, fileName: String) {
        let fileURL = directory.appendingPathComponent(fileName)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false
        ]

        do {
            let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder.delegate = self
            recorder.record()
            self.recorder = recorder
            self.currentFileURL = fileURL
            self.isRecording = true
        } catch {
            print("Failed to start recording: \(error)")
        }
    }

    /// Stops the current recording and returns the URL of the finished audio
    /// file, or nil if nothing was recording.
    @discardableResult
    func stopRecording() -> URL? {
        recorder?.stop()
        recorder = nil
        isRecording = false
        return currentFileURL
    }
}

// AVAudioRecorder needs a delegate object; we don't need to react to any of
// its callbacks ourselves, but this conformance is required to set `.delegate`.
extension AudioRecorder: AVAudioRecorderDelegate {}
