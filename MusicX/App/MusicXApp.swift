import SwiftUI

@main
struct MusicXApp: App {
    #if DEBUG && targetEnvironment(simulator)
    init() {
        let env = ProcessInfo.processInfo.environment
        guard let kind = env["QUEUE_TEST_KIND"], ["recent", "favorite"].contains(kind),
              let encoded = env["QUEUE_TEST_SONGS"], let data = Data(base64Encoded: encoded),
              let json = String(data: data, encoding: .utf8), let ids = env["QUEUE_TEST_IDS"] else { return }
        UserDefaults.standard.set(json, forKey: "musicx." + kind + "Songs")
        UserDefaults.standard.set(ids, forKey: "musicx." + kind + "IDs")
    }
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
