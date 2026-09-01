import SwiftUI

/// Lets you configure which LLM the summarization step calls: the API
/// endpoint, the model name, and the API key. Works with OpenAI itself, or
/// any other OpenAI-compatible endpoint (including a local server).
struct SettingsView: View {
    @ObservedObject var settings: LLMSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("LLM for Summaries") {
                TextField("API Base URL", text: $settings.baseURLString)
                TextField("Model", text: $settings.model)
                SecureField("API Key", text: $settings.apiKey)
            }
            Text("Must be an OpenAI-compatible chat completions endpoint. Works with OpenAI, and with other providers or local servers (LM Studio, Ollama's OpenAI-compatible mode, OpenRouter, Groq, etc.) that speak the same API shape.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 420)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}
