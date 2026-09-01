import Foundation
import SwiftUI

/// Holds the user's configuration for the summarization LLM: which endpoint
/// to call, which model, and the API key. Kept as its own ObservableObject
/// (separate from SummarizerService) so the Settings screen can bind
/// directly to these values with a two-way `$` binding.
///
/// Base URL and model name are plain settings (not secret), so they're saved
/// with UserDefaults. The API key IS secret, so it's saved to the Keychain
/// instead -- see KeychainHelper.
@MainActor
final class LLMSettings: ObservableObject {
    @Published var baseURLString: String {
        didSet { UserDefaults.standard.set(baseURLString, forKey: "llmBaseURL") }
    }
    @Published var model: String {
        didSet { UserDefaults.standard.set(model, forKey: "llmModel") }
    }
    @Published var apiKey: String {
        didSet {
            if apiKey.isEmpty {
                KeychainHelper.delete()
            } else {
                KeychainHelper.save(apiKey)
            }
        }
    }

    init() {
        baseURLString = UserDefaults.standard.string(forKey: "llmBaseURL")
            ?? "https://api.openai.com/v1/chat/completions"
        model = UserDefaults.standard.string(forKey: "llmModel") ?? "gpt-4o-mini"
        apiKey = KeychainHelper.load() ?? ""
    }
}
