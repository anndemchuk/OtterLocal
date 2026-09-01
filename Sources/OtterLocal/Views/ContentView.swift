import SwiftUI

/// The app's single main screen: a sidebar of past recordings on the left,
/// and on the right either (a) the recorder plus the transcript/summary of a
/// recording in progress, or (b) the transcript/summary of a past recording
/// you selected from the sidebar.
struct ContentView: View {
    @EnvironmentObject private var store: RecordingStore

    // These three objects do the actual work; ContentView just wires them
    // together and reacts to their published state.
    @StateObject private var audioRecorder = AudioRecorder()
    @StateObject private var transcriber = Transcriber()
    @StateObject private var llmSettings = LLMSettings()

    // nil means "show the live recording view" instead of a saved past recording.
    @State private var selectedRecordingID: Recording.ID?
    @State private var showingSettings = false

    // The recording currently being captured/processed, if any.
    @State private var activeRecording: Recording?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    // Progress text for the summarization step specifically (e.g. "Summarizing
    // part 4 of 12..." on a long lecture) -- shown once transcription's own
    // status message has cleared.
    @State private var summaryStatus = ""

    var body: some View {
        NavigationSplitView {
            RecordingsListView(selection: $selectedRecordingID, onNewRecording: {
                selectedRecordingID = nil
            })
        } detail: {
            detailView
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        Button {
                            showingSettings = true
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    }
                }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(settings: llmSettings)
        }
        .onChange(of: audioRecorder.permissionDenied) { _, denied in
            if denied {
                errorMessage = "Microphone access was denied. Enable it in System Settings > Privacy & Security > Microphone, then try again."
            }
        }
        .onChange(of: store.lastError) { _, message in
            if let message {
                errorMessage = message
                store.lastError = nil
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var detailView: some View {
        if let id = selectedRecordingID, let saved = store.recordings.first(where: { $0.id == id }) {
            // Viewing a past recording: read-only.
            RecordingDetailView(recording: saved)
        } else {
            // Live recording view: shows the record button plus whatever
            // transcript/summary we have so far for the in-progress recording.
            RecordingDetailView(
                recording: activeRecording ?? Recording(title: "New Recording", audioFileName: ""),
                isLive: true,
                isProcessing: isProcessing,
                statusMessage: summaryStatus.isEmpty ? transcriber.statusMessage : summaryStatus,
                isRecording: audioRecorder.isRecording,
                onRecordTapped: toggleRecording
            )
        }
    }

    private func toggleRecording() {
        if audioRecorder.isRecording {
            stopAndProcess()
        } else {
            startNewRecording()
        }
    }

    private func startNewRecording() {
        let recording = Recording(
            title: "Recording \(Date().formatted(date: .abbreviated, time: .shortened))",
            audioFileName: ""
        )
        activeRecording = recording
        let fileURL = store.newAudioFileURL(for: recording.id)
        audioRecorder.startRecording(into: store.audioDirectory, fileName: fileURL.lastPathComponent)
    }

    private func stopAndProcess() {
        guard let fileURL = audioRecorder.stopRecording(), var recording = activeRecording else { return }

        // Save the recording immediately (with an empty transcript) so it's
        // never lost even if transcription or summarization fails partway.
        recording.audioFileName = fileURL.lastPathComponent
        activeRecording = recording
        store.add(recording)
        selectedRecordingID = nil

        isProcessing = true
        summaryStatus = ""
        Task {
            do {
                let transcript = try await transcriber.transcribe(fileURL: fileURL)
                recording.transcript = transcript
                activeRecording = recording
                store.update(recording)

                let summaryService = SummarizerService(settings: llmSettings)
                let result = try await summaryService.summarize(transcript: transcript) { status in
                    summaryStatus = status
                }
                recording.lessonTopic = result.lessonTopic
                recording.keyConcepts = result.keyConcepts
                recording.examplesUsed = result.examplesUsed
                recording.importantTakeaways = result.importantTakeaways
                recording.questionsRaised = result.questionsRaised
                recording.actionItems = result.actionItems
                activeRecording = recording
                store.update(recording)
            } catch {
                errorMessage = error.localizedDescription
            }
            summaryStatus = ""
            isProcessing = false
        }
    }
}
