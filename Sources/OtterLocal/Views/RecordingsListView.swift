import SwiftUI

/// The sidebar: a button to start a new recording, plus the list of past
/// recordings (title + date) you can tap into to review them. Right-click a
/// recording to rename or delete it.
struct RecordingsListView: View {
    @EnvironmentObject private var store: RecordingStore
    @Binding var selection: Recording.ID?
    var onNewRecording: () -> Void

    // Which recording (if any) is currently being renamed, and the text
    // being typed into the rename field.
    @State private var renamingRecording: Recording?
    @State private var renameText = ""

    // Which recording (if any) is waiting on a "are you sure?" before we
    // actually delete it -- deleting removes the audio file permanently.
    @State private var recordingPendingDelete: Recording?

    var body: some View {
        List(selection: $selection) {
            Section {
                Button(action: onNewRecording) {
                    Label("New Recording", systemImage: "plus.circle")
                }
            }
            Section("Past Recordings") {
                ForEach(store.recordings) { recording in
                    HStack(alignment: .top, spacing: 8) {
                        if let tagColor = recording.tagColor {
                            Circle()
                                .fill(tagColor.color)
                                .frame(width: 8, height: 8)
                                .padding(.top, 5)
                        }
                        VStack(alignment: .leading) {
                            Text(recording.title)
                            Text(recording.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(recording.id as Recording.ID?)
                    .contextMenu {
                        Button("Rename...") {
                            renamingRecording = recording
                            renameText = recording.title
                        }
                        Menu("Tag") {
                            ForEach(TagColor.allCases) { tagColor in
                                Button("\(tagColor.emoji) \(tagColor.label)\(recording.tagColor == tagColor ? " \u{2713}" : "")") {
                                    setTag(tagColor, on: recording)
                                }
                            }
                            if recording.tagColor != nil {
                                Divider()
                                Button("None") { setTag(nil, on: recording) }
                            }
                        }
                        Button("Delete", role: .destructive) {
                            recordingPendingDelete = recording
                        }
                    }
                }
            }
        }
        .navigationTitle("OtterLocal")
        .frame(minWidth: 220)
        .alert(
            "Rename Recording",
            isPresented: Binding(
                get: { renamingRecording != nil },
                set: { isPresented in if !isPresented { renamingRecording = nil } }
            )
        ) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) { renamingRecording = nil }
            Button("Save") {
                guard var recording = renamingRecording else { return }
                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    recording.title = trimmed
                    store.update(recording)
                }
                renamingRecording = nil
            }
        }
        .confirmationDialog(
            "Delete this recording?",
            isPresented: Binding(
                get: { recordingPendingDelete != nil },
                set: { isPresented in if !isPresented { recordingPendingDelete = nil } }
            ),
            presenting: recordingPendingDelete
        ) { recording in
            Button("Delete \"\(recording.title)\"", role: .destructive) {
                store.delete(recording)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This moves the audio file to Trash and permanently deletes its transcript and summary from OtterLocal.")
        }
    }

    private func setTag(_ tagColor: TagColor?, on recording: Recording) {
        var updated = recording
        updated.tagColor = tagColor
        store.update(updated)
    }
}
