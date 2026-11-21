import SwiftUI

@main
struct MusicXApp: App {
    #if DEBUG && targetEnvironment(simulator)
    init() {
        let env = ProcessInfo.processInfo.environment
        guard let kind = env["QUEUE_TEST_KIND"], ["recent", "favorite"].contains(kind),
              let encoded = env["QUEUE_TEST_SONGS"], let data = Data(base64Encoded: encoded),
              let json = String(data: data, encoding: .utf8), let ids = env["QUEUE_TEST_IDS"] else { return }
        for prefix in ["recent", "favorite"] {
            UserDefaults.standard.set(json, forKey: "musicx." + prefix + "Songs")
            UserDefaults.standard.set(ids, forKey: "musicx." + prefix + "IDs")
        }
        let old = ["source": "wy", "sourceID": "old", "title": "Previous session", "artist": "Fixture"]
        let saved: [String: Any] = ["song": old, "queue": [old], "position": 12.0]
        UserDefaults.standard.set(try? JSONSerialization.data(withJSONObject: saved),
                                  forKey: "musicx.playback-session.v1")
    }
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
