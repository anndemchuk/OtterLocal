import Foundation
import WhisperKit

/// Wraps WhisperKit so the rest of the app can just say "transcribe this
/// file" without knowing anything about CoreML or model loading.
///
/// WhisperKit downloads the Whisper model from Hugging Face the FIRST time
/// it's used, then caches it on disk -- every run after that is fully
/// offline. This is what makes transcription free: there's no API, no
/// account, and no per-minute charge, just your Mac's own compute.
@MainActor
final class Transcriber: ObservableObject {
    @Published var isBusy = false
    @Published var statusMessage = ""

    private var whisperKit: WhisperKit?

    private func loadModelIfNeeded() async throws {
        guard whisperKit == nil else { return }
        statusMessage = "Loading Whisper model (first run downloads it)..."

        // "base.en" is a good balance of speed vs. accuracy for English
        // lecture audio on a laptop. If accuracy matters more than speed to
        // you, try "small.en" or "large-v3-v20240930_626MB" instead -- just
        // change the string below. Drop the ".en" suffix on any model name to
        // support languages other than English.
        let config = WhisperKitConfig(model: "base.en")
        whisperKit = try await WhisperKit(config)
    }

    /// Transcribes an audio file on disk and returns the full text.
    func transcribe(fileURL: URL) async throws -> String {
        isBusy = true
        defer {
            isBusy = false
            statusMessage = ""
        }

        try await loadModelIfNeeded()
        guard let whisperKit else { return "" }

        statusMessage = "Transcribing..."
        // Long recordings get split into chunks internally by WhisperKit, so
        // `transcribe` can return more than one result -- we just join their
        // text back together into one continuous transcript.
        let results = try await whisperKit.transcribe(audioPath: fileURL.path)
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
