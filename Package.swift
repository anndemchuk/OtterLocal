// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "OtterLocal",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        // WhisperKit runs OpenAI's Whisper speech-to-text model fully on-device
        // via Apple's CoreML framework / Neural Engine. No network calls (after
        // the one-time model download), no API key, and no per-minute cost --
        // this is what keeps transcription free and offline.
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "0.9.0")
    ],
    targets: [
        .executableTarget(
            name: "OtterLocal",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift")
            ],
            path: "Sources/OtterLocal"
        )
    ]
)
