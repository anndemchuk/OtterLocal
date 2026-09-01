import SwiftUI

/// Shows one recording's transcript and summary.
///
/// When `isLive` is true this is the "recording in progress" view, and it
/// also shows the record/stop button and a processing spinner. When false,
/// it's a read-only view of a past, already-saved recording.
struct RecordingDetailView: View {
    let recording: Recording
    var isLive: Bool = false
    var isProcessing: Bool = false
    var statusMessage: String = ""
    var isRecording: Bool = false
    var onRecordTapped: (() -> Void)? = nil

    // Collapsed by default -- the transcript is usually the longest part of
    // the screen (especially for a full lecture), so we don't want it
    // pushing the summary out of view.
    @State private var isTranscriptExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(recording.title)
                .font(.title2)
                .bold()

            if isLive {
                recordControls
            }

            if isProcessing {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(statusMessage.isEmpty ? "Processing..." : statusMessage)
                        .foregroundStyle(.secondary)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if recording.lessonTopic.isEmpty {
                        section(title: "Summary") {
                            Text("No summary yet.")
                        }
                    } else {
                        section(title: "Lesson Topic") {
                            Text(recording.lessonTopic)
                        }
                        bulletSection(title: "Key Concepts", items: recording.keyConcepts)
                        bulletSection(title: "Examples Used", items: recording.examplesUsed)
                        bulletSection(title: "Important Takeaways", items: recording.importantTakeaways)
                        bulletSection(title: "Questions Raised", items: recording.questionsRaised)
                        bulletSection(title: "Action Items", items: recording.actionItems)
                    }

                    DisclosureGroup("Transcript", isExpanded: $isTranscriptExpanded) {
                        Text(recording.transcript.isEmpty ? "No transcript yet." : recording.transcript)
                            .textSelection(.enabled)
                            .padding(.top, 6)
                    }
                    .font(.headline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
    }

    private var recordControls: some View {
        Button(action: { onRecordTapped?() }) {
            Label(isRecording ? "Stop Recording" : "Start Recording",
                  systemImage: isRecording ? "stop.circle.fill" : "record.circle")
                .font(.title3)
        }
        .buttonStyle(.borderedProminent)
        .tint(isRecording ? .red : .accentColor)
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            content()
                .textSelection(.enabled)
        }
    }

    /// One summary section rendered as a bulleted list -- skipped entirely
    /// if there's nothing in it (e.g. a lesson with no open questions).
    @ViewBuilder
    private func bulletSection(title: String, items: [String]) -> some View {
        if !items.isEmpty {
            section(title: title) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(items, id: \.self) { item in
                        HStack(alignment: .top, spacing: 6) {
                            Text("\u{2022}")
                            Text(item)
                        }
                    }
                }
            }
        }
    }
}
