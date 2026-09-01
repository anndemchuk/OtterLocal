import Foundation

/// The structured lesson summary the LLM produces from a transcript, split
/// into the sections the summarization prompt asks for.
struct LessonSummary {
    var lessonTopic: String
    var keyConcepts: [String]
    var examplesUsed: [String]
    var importantTakeaways: [String]
    var questionsRaised: [String]
    var actionItems: [String]
}

enum SummarizerError: LocalizedError {
    case missingAPIKey
    case invalidBaseURL
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No API key configured. Open Settings and add one."
        case .invalidBaseURL:
            return "The configured API URL is not valid."
        case .badResponse(let message):
            return "The summarization request failed: \(message)"
        }
    }
}

/// Sends the transcript to an LLM and asks it for a structured lesson
/// summary: topic, key concepts, examples, takeaways, open questions, and
/// action items.
///
/// This speaks the OpenAI "chat completions" API format, which is also
/// supported by many other providers and local servers (OpenRouter, Groq,
/// LM Studio, Ollama's OpenAI-compatible mode, etc). That's why the base
/// URL, model name, and API key are all configurable in Settings instead of
/// hard-coded to one provider -- point it at whichever one you like.
///
/// Long transcripts (e.g. a 1.5-2 hour lecture) can easily be 15,000+ words,
/// which is more than many LLMs -- especially local models run through
/// Ollama -- will actually read in one request; the rest just gets silently
/// dropped. To avoid that, long transcripts are split into chunks and each
/// chunk is summarized on its own, in the same six-section format.
///
/// Those per-chunk summaries are then combined WITHOUT another LLM call for
/// most sections -- their key concepts, examples, takeaways, questions, and
/// action items are just concatenated (with exact-duplicate lines removed).
/// Asking a small local model to re-read and re-synthesize a whole lecture's
/// worth of notes in one shot turns out to lose things -- in testing, a
/// 3-topic transcript came back with one topic silently dropped when that
/// step was an LLM call. Plain concatenation can't lose anything, since
/// nothing is being re-generated. Only the one-sentence overall "lesson
/// topic" needs an LLM call to combine, and that's a small, low-risk input
/// (a handful of short sentences, not the whole lecture). Short transcripts
/// that fit in a single chunk skip all of this and summarize in one call.
@MainActor
struct SummarizerService {
    let settings: LLMSettings

    /// Transcripts longer than this (in words) get chunked before
    /// summarizing. ~900 words keeps each request comfortably inside even a
    /// small 2048-token context window once you account for the prompt
    /// instructions and the model's reply.
    private let maxWordsPerChunk = 900

    /// The exact structure every summary should follow, and the rules for
    /// producing it. This part mirrors what you'd tell a person doing this
    /// task by hand -- the ALL-CAPS headers layered on top (in `finalPrompt`)
    /// are just there so our code can reliably split the model's reply back
    /// into sections afterwards.
    private let formatInstructions = """
    You are an assistant that summarizes lesson transcripts for students and teachers.
    Read the transcript carefully and create a clear summary covering:

    1. Lesson topic - one sentence stating what the lesson covered.
    2. Key concepts - the main ideas or terms explained, with a short explanation for each.
    3. Examples used - any examples, case studies, or problems the instructor walked through.
    4. Important takeaways - the points the instructor emphasized as critical to remember.
    5. Questions raised - any questions asked by students or the instructor that stayed open or need follow up.
    6. Action items - homework, readings, or tasks assigned during the lesson.

    Rules:
    - Use plain language, no jargon unless the lesson itself used it.
    - Keep the summary under 400 words unless the transcript covers multiple topics.
    - Do not add information that isn't in the transcript.
    - If the transcript is unclear or cuts off, say so instead of guessing.
    """

    /// Called with a short human-readable status (e.g. "Summarizing part 2 of 12...")
    /// so the UI can show progress on long transcripts.
    func summarize(transcript: String, onProgress: (String) -> Void = { _ in }) async throws -> LessonSummary {
        guard !settings.apiKey.isEmpty else { throw SummarizerError.missingAPIKey }
        guard URL(string: settings.baseURLString) != nil else { throw SummarizerError.invalidBaseURL }

        let chunks = chunk(transcript, maxWords: maxWordsPerChunk)

        if chunks.count <= 1 {
            onProgress("Summarizing...")
            return try await summarizeSection(transcript, partIndex: 1, totalParts: 1)
        }

        var sectionSummaries: [LessonSummary] = []
        for (index, chunkText) in chunks.enumerated() {
            onProgress("Summarizing part \(index + 1) of \(chunks.count)...")
            let summary = try await summarizeSection(chunkText, partIndex: index + 1, totalParts: chunks.count)
            sectionSummaries.append(summary)
        }

        onProgress("Combining into a final summary...")
        return try await combine(sectionSummaries)
    }

    /// Summarizes one piece of the transcript (the whole thing, if it fits in
    /// a single chunk) in the six-section format. When `totalParts` is more
    /// than 1, the model is told this is only a slice of a longer transcript
    /// so it doesn't try to guess at content it can't see.
    private func summarizeSection(_ text: String, partIndex: Int, totalParts: Int) async throws -> LessonSummary {
        let isPartial = totalParts > 1
        let partContext = isPartial
            ? "This is part \(partIndex) of \(totalParts) of a longer lesson transcript, taken in order. Only report what's actually discussed in THIS part -- don't guess at what might be covered elsewhere.\n\n"
            : ""
        let sourceLabel = isPartial ? "Part \(partIndex) of \(totalParts):" : "Transcript:"

        let prompt = """
        \(formatInstructions)

        \(partContext)Respond in exactly this format, with no extra commentary before or after. If a section has nothing to report, write "None noted." under its header instead of skipping it.

        LESSON TOPIC:
        <one sentence>
        KEY CONCEPTS:
        - <concept>: <short explanation>
        EXAMPLES USED:
        - <example>
        IMPORTANT TAKEAWAYS:
        - <takeaway>
        QUESTIONS RAISED:
        - <question>
        ACTION ITEMS:
        - <item>

        \(sourceLabel)
        \(text)
        """
        let content = try await request(prompt: prompt)
        return parse(content)
    }

    /// Combines the per-chunk summaries of a long transcript into one final
    /// summary. Every section except the topic is a plain concatenation
    /// (with exact-duplicate lines dropped) -- no LLM involved, so nothing
    /// from any chunk can get lost or rewritten. The topic sentence is the
    /// one piece that genuinely needs synthesizing across chunks, so that
    /// gets a single small LLM call over just the short per-chunk topics.
    private func combine(_ summaries: [LessonSummary]) async throws -> LessonSummary {
        guard summaries.count > 1 else {
            return summaries.first ?? LessonSummary(
                lessonTopic: "", keyConcepts: [], examplesUsed: [],
                importantTakeaways: [], questionsRaised: [], actionItems: []
            )
        }

        func dedupedConcat(_ lists: [[String]]) -> [String] {
            var seen = Set<String>()
            var result: [String] = []
            for item in lists.flatMap({ $0 }) {
                let key = item.lowercased().trimmingCharacters(in: .whitespaces)
                guard !key.isEmpty, !seen.contains(key) else { continue }
                seen.insert(key)
                result.append(item)
            }
            return result
        }

        let topics = summaries.map(\.lessonTopic).filter { !$0.isEmpty }
        let overallTopic: String
        if topics.count <= 1 {
            overallTopic = topics.first ?? ""
        } else {
            let topicPrompt = """
            These are the topics covered by consecutive parts of one longer lesson, in order:
            \(topics.enumerated().map { "\($0 + 1). \($1)" }.joined(separator: "\n"))

            Write one sentence describing what the lesson as a whole covered. If it covered multiple distinct topics, say so and name them briefly.
            """
            overallTopic = try await request(prompt: topicPrompt).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return LessonSummary(
            lessonTopic: overallTopic,
            keyConcepts: dedupedConcat(summaries.map(\.keyConcepts)),
            examplesUsed: dedupedConcat(summaries.map(\.examplesUsed)),
            importantTakeaways: dedupedConcat(summaries.map(\.importantTakeaways)),
            questionsRaised: dedupedConcat(summaries.map(\.questionsRaised)),
            actionItems: dedupedConcat(summaries.map(\.actionItems))
        )
    }

    /// Sends one chat-completion request and returns the assistant's reply text.
    private func request(prompt: String) async throws -> String {
        let url = URL(string: settings.baseURLString)! // already validated by the caller

        let requestBody: [String: Any] = [
            "model": settings.model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.3
        ]

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? "unknown error"
            throw SummarizerError.badResponse(bodyText)
        }

        return try extractContent(from: data)
    }

    /// Splits a transcript into word chunks of at most `maxWords` words each,
    /// breaking on whitespace so we never cut a word in half.
    private func chunk(_ text: String, maxWords: Int) -> [String] {
        let words = text.split(whereSeparator: { $0.isWhitespace })
        guard !words.isEmpty else { return [] }

        var chunks: [String] = []
        var start = 0
        while start < words.count {
            let end = min(start + maxWords, words.count)
            chunks.append(words[start..<end].joined(separator: " "))
            start = end
        }
        return chunks
    }

    /// Pulls the assistant's reply text out of an OpenAI-shaped chat
    /// completion response, i.e. `{ "choices": [{ "message": { "content": "..." } }] }`.
    private func extractContent(from data: Data) throws -> String {
        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let text = decoded.choices.first?.message.content else {
            throw SummarizerError.badResponse("No content in response")
        }
        return text
    }

    /// Splits the model's reply into the six sections by finding each
    /// ALL-CAPS header and taking everything up to the next one found. A
    /// header the model skipped just ends up with an empty section rather
    /// than breaking the rest of the parse.
    private func parse(_ text: String) -> LessonSummary {
        let headers = [
            "LESSON TOPIC:", "KEY CONCEPTS:", "EXAMPLES USED:",
            "IMPORTANT TAKEAWAYS:", "QUESTIONS RAISED:", "ACTION ITEMS:"
        ]

        let found = headers.enumerated()
            .compactMap { index, header -> (index: Int, range: Range<String.Index>)? in
                guard let range = text.range(of: header) else { return nil }
                return (index, range)
            }
            .sorted { $0.range.lowerBound < $1.range.lowerBound }

        guard !found.isEmpty else {
            // The model ignored the format entirely -- rather than lose the
            // reply, surface it as the topic so it's still visible somewhere.
            return LessonSummary(
                lessonTopic: text.trimmingCharacters(in: .whitespacesAndNewlines),
                keyConcepts: [], examplesUsed: [], importantTakeaways: [], questionsRaised: [], actionItems: []
            )
        }

        var bodies = [String](repeating: "", count: headers.count)
        for (position, entry) in found.enumerated() {
            let start = entry.range.upperBound
            let end = position + 1 < found.count ? found[position + 1].range.lowerBound : text.endIndex
            bodies[entry.index] = String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func bulletList(_ body: String) -> [String] {
            body.split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && $0.lowercased() != "none noted." }
                .map { line -> String in
                    if line.hasPrefix("- ") || line.hasPrefix("* ") {
                        return String(line.dropFirst(2))
                    }
                    return line
                }
        }

        return LessonSummary(
            lessonTopic: bodies[0],
            keyConcepts: bulletList(bodies[1]),
            examplesUsed: bulletList(bodies[2]),
            importantTakeaways: bulletList(bodies[3]),
            questionsRaised: bulletList(bodies[4]),
            actionItems: bulletList(bodies[5])
        )
    }
}
