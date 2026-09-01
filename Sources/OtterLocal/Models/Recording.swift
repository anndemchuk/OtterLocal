import Foundation

/// A single saved lecture/meeting recording: a pointer to its audio file, the
/// transcript Whisper produced from it, and the structured lesson summary the
/// LLM produced from that transcript.
///
/// `Codable` means Swift can automatically turn this into JSON and back --
/// that's how RecordingStore saves the list of recordings to disk.
/// `Identifiable` is what lets SwiftUI lists (like RecordingsListView) tell
/// each recording apart.
struct Recording: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var date: Date

    /// Just the file name (e.g. "3F2A...wav"), not a full path. The actual
    /// audio file lives in RecordingStore's audioDirectory. Storing only the
    /// name (rather than a full path) means recordings still work correctly
    /// even if the app's data folder ever moves.
    var audioFileName: String

    var transcript: String

    // The summary the LLM produces, split into the six sections the
    // summarization prompt asks for (see SummarizerService). Each is empty
    // until summarization finishes.
    var lessonTopic: String
    var keyConcepts: [String]
    var examplesUsed: [String]
    var importantTakeaways: [String]
    var questionsRaised: [String]
    var actionItems: [String]

    /// An optional colored tag (see TagColor), set via the sidebar's
    /// right-click menu. nil means "no tag".
    var tagColor: TagColor?

    init(
        id: UUID = UUID(),
        title: String,
        date: Date = Date(),
        audioFileName: String,
        transcript: String = "",
        lessonTopic: String = "",
        keyConcepts: [String] = [],
        examplesUsed: [String] = [],
        importantTakeaways: [String] = [],
        questionsRaised: [String] = [],
        actionItems: [String] = [],
        tagColor: TagColor? = nil
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.audioFileName = audioFileName
        self.transcript = transcript
        self.lessonTopic = lessonTopic
        self.keyConcepts = keyConcepts
        self.examplesUsed = examplesUsed
        self.importantTakeaways = importantTakeaways
        self.questionsRaised = questionsRaised
        self.actionItems = actionItems
        self.tagColor = tagColor
    }

    // A custom decoder so recordings saved by an older version of the app
    // (back when there was just one "summary" string and a flat "keyPoints"
    // list) still load instead of vanishing from the sidebar -- any of these
    // newer fields that aren't in the saved JSON just default to empty.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        date = try container.decode(Date.self, forKey: .date)
        audioFileName = try container.decode(String.self, forKey: .audioFileName)
        transcript = try container.decodeIfPresent(String.self, forKey: .transcript) ?? ""
        lessonTopic = try container.decodeIfPresent(String.self, forKey: .lessonTopic) ?? ""
        keyConcepts = try container.decodeIfPresent([String].self, forKey: .keyConcepts) ?? []
        examplesUsed = try container.decodeIfPresent([String].self, forKey: .examplesUsed) ?? []
        importantTakeaways = try container.decodeIfPresent([String].self, forKey: .importantTakeaways) ?? []
        questionsRaised = try container.decodeIfPresent([String].self, forKey: .questionsRaised) ?? []
        actionItems = try container.decodeIfPresent([String].self, forKey: .actionItems) ?? []
        tagColor = try container.decodeIfPresent(TagColor.self, forKey: .tagColor)
    }
}
