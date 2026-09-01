import SwiftUI

/// The entry point of the app. Every SwiftUI app starts here: this struct's
/// `body` describes the window(s) our app shows. The `@main` attribute tells
/// Swift "this is where the program begins".
@main
struct OtterLocalApp: App {
    // RecordingStore owns the list of saved recordings and reads/writes them
    // to disk. We create ONE instance here and hand it down to every view
    // that needs it (via .environmentObject below), so there's a single
    // source of truth for "what have I recorded so far".
    @StateObject private var store = RecordingStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 800, minHeight: 500)
        }
    }
}
