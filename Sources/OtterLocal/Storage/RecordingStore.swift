import Foundation
import SwiftUI

/// Keeps the list of saved recordings in memory and persists them to disk so
/// they survive app restarts. Everything this app saves lives under
/// ~/Library/Application Support/OtterLocal/ :
///
///   recordings.json     a JSON array describing every saved Recording
///   Audio/<uuid>.wav     the raw audio file for each recording
///
/// `ObservableObject` + `@Published` is SwiftUI's way of saying "when
/// `recordings` changes, redraw any view that's reading it".
@MainActor
final class RecordingStore: ObservableObject {
    @Published private(set) var recordings: [Recording] = []

    /// Set when something goes wrong that the user should know about but
    /// that isn't severe enough to lose data over (e.g. a recording's audio
    /// file couldn't be deleted). The UI can observe this and show an alert.
    @Published var lastError: String?

    /// Folder where everything this app saves lives.
    let appSupportDirectory: URL
    /// Subfolder specifically for audio files, kept separate from the JSON index.
    let audioDirectory: URL
    private let indexFileURL: URL
    /// A copy of the index from just before the last write. If a future
    /// version of the app ever fails to read recordings.json (a bad decode,
    /// a corrupted write, etc.), this is what stands between that and
    /// silently losing every past recording.
    private let backupFileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        appSupportDirectory = base.appendingPathComponent("OtterLocal", isDirectory: true)
        audioDirectory = appSupportDirectory.appendingPathComponent("Audio", isDirectory: true)
        indexFileURL = appSupportDirectory.appendingPathComponent("recordings.json")
        backupFileURL = appSupportDirectory.appendingPathComponent("recordings.backup.json")

        // Make sure our folders exist before we try to read/write anything.
        try? FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)

        load()
    }

    /// Returns the file URL (inside audioDirectory) that a new recording with
    /// this id should be recorded into. Naming the file after the recording's
    /// id keeps every audio file's name unique automatically.
    func newAudioFileURL(for id: UUID) -> URL {
        audioDirectory.appendingPathComponent("\(id.uuidString).wav")
    }

    /// Adds a recording to the in-memory list (newest first) and saves the
    /// index to disk.
    func add(_ recording: Recording) {
        recordings.insert(recording, at: 0)
        save()
    }

    /// Overwrites an existing recording -- used once transcription/summary
    /// finish and we need to save the updated text -- and saves to disk.
    func update(_ recording: Recording) {
        guard let index = recordings.firstIndex(where: { $0.id == recording.id }) else { return }
        recordings[index] = recording
        save()
    }

    /// Moves a recording's audio file to the Trash and removes it from the
    /// list -- but only once the file is actually confirmed gone from its
    /// original location. If that fails (e.g. the file is briefly locked by
    /// something else), the recording is left in the list rather than
    /// silently orphaning its audio file, and `lastError` is set so the UI
    /// can tell you what happened.
    ///
    /// Using the Trash (instead of permanently deleting) means the audio is
    /// still recoverable if you delete the wrong recording by mistake --
    /// same as dragging a file to Trash in Finder. The transcript and
    /// summary aren't stored anywhere except this app's index though, so
    /// those really are gone for good once you confirm.
    func delete(_ recording: Recording) {
        let audioURL = audioDirectory.appendingPathComponent(recording.audioFileName)
        if FileManager.default.fileExists(atPath: audioURL.path) {
            do {
                try FileManager.default.trashItem(at: audioURL, resultingItemURL: nil)
            } catch {
                lastError = "Couldn't delete the audio file for \"\(recording.title)\": \(error.localizedDescription). Nothing was removed -- try again."
                return
            }
        }
        recordings.removeAll { $0.id == recording.id }
        save()
    }

    /// Decodes the saved index leniently: each recording is decoded on its
    /// own, so one entry in a shape this version of the app doesn't
    /// recognize (e.g. saved by an older version) can't take every other
    /// recording down with it -- that entry is just skipped instead.
    private func load() {
        if let data = try? Data(contentsOf: indexFileURL), let decoded = decodeLeniently(data) {
            recordings = decoded
            return
        }
        // The main index was missing or unreadable -- fall back to the
        // backup from the last successful save, rather than starting empty.
        if let data = try? Data(contentsOf: backupFileURL), let decoded = decodeLeniently(data) {
            recordings = decoded
        }
    }

    private func decodeLeniently(_ data: Data) -> [Recording]? {
        struct Box: Decodable {
            let recording: Recording?
            init(from decoder: Decoder) {
                recording = try? Recording(from: decoder)
            }
        }
        guard let boxes = try? JSONDecoder().decode([Box].self, from: data) else { return nil }
        return boxes.compactMap(\.recording)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(recordings) else { return }
        // Keep one rolling backup of the index as it was before this write,
        // so a future bad write or bad decode has something to fall back to
        // instead of every past recording just disappearing.
        if FileManager.default.fileExists(atPath: indexFileURL.path) {
            try? FileManager.default.removeItem(at: backupFileURL)
            try? FileManager.default.copyItem(at: indexFileURL, to: backupFileURL)
        }
        try? data.write(to: indexFileURL, options: .atomic)
    }
}
