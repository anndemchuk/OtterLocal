# OtterLocal

A free, fully local alternative to Otter.ai for macOS: record a lecture or meeting, transcribe it offline with [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift), and summarize it with a locally-run or cloud LLM of your choice.

- **Transcription** is 100% local and free (WhisperKit + CoreML). The model downloads once from Hugging Face on first use, then works fully offline.
- **Summarization** calls any OpenAI-compatible chat endpoint you configure in Settings -- a local [Ollama](https://ollama.com) model (free, offline) or a cloud provider (OpenAI, Groq, etc.).

## Requirements

- macOS 14 or later.
- A Swift toolchain. Xcode's Command Line Tools are enough -- **full Xcode is not required**. Check with:
  ```bash
  swift --version
  ```
- For local summarization (recommended, free): [Ollama](https://ollama.com).

## Setting up on a new machine

This project is a Swift Package (no `.xcodeproj`), so it builds from the command line without Xcode. A few one-time setup steps live outside the code, though, so a plain `git clone` isn't quite enough on its own -- do these once per machine:

### 1. Clone and build

```bash
git clone <this-repo-url> OtterLocal
cd OtterLocal
swift build
```

If that compiles, the code and dependencies are all fine.

### 2. Create a local code-signing certificate

macOS ties microphone permission and Keychain access to an app's code signature. Building with an ad-hoc signature (the default) means every rebuild looks like "a new app" to macOS, and you get re-prompted for permissions constantly. To avoid that, create a free, local, self-signed certificate once:

1. Open **Keychain Access** (Applications → Utilities).
2. Menu bar: **Keychain Access → Certificate Assistant → Create a Certificate...**
3. **Name:** `OtterLocal Local Signing` (must match exactly -- `build_app.sh` references this name)
4. **Identity Type:** Self Signed Root
5. **Certificate Type:** Code Signing
6. Click **Create**, then **Done**.
7. In Keychain Access, find it under **My Certificates**, double-click it, expand **Trust**, and set **Code Signing** to **Always Trust**. Confirm with your login password.

Verify it's usable:
```bash
security find-identity -v -p codesigning
```
You should see `OtterLocal Local Signing` in the list.

### 3. Build the app bundle

```bash
./build_app.sh
open OtterLocal.app
```

This compiles a release build, bundles it into a proper `.app` (with icon and `Info.plist`), and signs it with the certificate from step 2. On first launch you'll be asked for microphone access -- allow it. Because of the stable certificate, this should be the last time you're asked (rebuilds won't re-trigger it).

### 4. Set up summarization

**Option A -- local and free (recommended):**
```bash
brew install ollama
brew services start ollama
ollama pull llama3.2
```
Then in OtterLocal's Settings (gear icon):
- **API Base URL:** `http://localhost:11434/v1/chat/completions`
- **Model:** `llama3.2`
- **API Key:** any non-empty placeholder text (e.g. `ollama`) -- Ollama doesn't check it, but the field can't be blank

**Option B -- a cloud provider** (OpenAI, Groq, etc.): put that provider's chat-completions URL, model name, and a real API key in Settings instead.

## Where your data lives

Recordings, transcripts, and summaries are stored **outside this repo**, at:
```
~/Library/Application Support/OtterLocal/
```
This is intentional -- recordings are personal audio data and shouldn't end up in git. Cloning this repo on a new machine gets you the *app*, not your past recordings; if you want those too, copy that folder over separately (e.g. via AirDrop, an external drive, or Time Machine).

## Project layout

```
Sources/OtterLocal/
├── Models/          -- Recording, TagColor
├── Storage/          -- RecordingStore (reads/writes recordings.json)
├── Audio/             -- AudioRecorder (AVFoundation mic capture)
├── Transcription/    -- Transcriber (wraps WhisperKit)
├── Summarization/   -- SummarizerService, LLMSettings, KeychainHelper
└── Views/              -- ContentView, RecordingsListView, RecordingDetailView, SettingsView
```

## Rebuilding after code changes

```bash
swift build           # quick compile check
./build_app.sh         # release build + repackage the .app
open OtterLocal.app
```
