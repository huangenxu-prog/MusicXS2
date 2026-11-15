import Foundation

/// Standalone macOS smoke test for the LX JavaScriptCore bridge.
/// Run: swiftc -framework JavaScriptCore MusicX/ResourceEngine/LXCompatibility/LXSourceScriptHost.swift scripts/test-lx-bridge.swift -o /tmp/test-lx-bridge && /tmp/test-lx-bridge
@main
struct LXBridgeSmokeTest {
    static func main() async {
        do {
            try await run()
            print("LX_BRIDGE_SMOKE_TEST_PASS")
        } catch {
            fputs("LX_BRIDGE_SMOKE_TEST_FAIL: \(error)\n", stderr)
            exit(1)
        }
    }

    @MainActor
    static func run() async throws {
        let script = """
        const { EVENT_NAMES, on, send } = globalThis.lx;
        on(EVENT_NAMES.request, async ({ action, source, info }) => {
          if (action !== 'musicUrl' || source !== 'tx') throw new Error('wrong event');
          if (info.musicInfo.songmid !== 'TESTMID' || info.type !== '320k') {
            throw new Error('wrong song payload');
          }
          return 'https://example.com/test.mp3';
        });
        send(EVENT_NAMES.inited, {
          status: true,
          sources: { tx: { name: 'QQ', type: 'music', actions: ['musicUrl'] } }
        });
        """
        let host = try LXSourceScriptHost(script: script)
        guard host.registeredSources["tx"] != nil else {
            throw NSError(domain: "LXSmoke", code: 1, userInfo: [NSLocalizedDescriptionKey: "init event lost"])
        }
        let url = try await host.resolve(source: "tx", musicInfo: ["songmid": "TESTMID"])
        guard url.absoluteString == "https://example.com/test.mp3" else {
            throw NSError(domain: "LXSmoke", code: 2, userInfo: [NSLocalizedDescriptionKey: "unexpected URL"])
        }

        let broken = try LXSourceScriptHost(script: """
        globalThis.lx.on(globalThis.lx.EVENT_NAMES.request, () => Promise.reject(new Error('expected failure')));
        globalThis.lx.send(globalThis.lx.EVENT_NAMES.inited, { sources: { tx: {} } });
        """)
        do {
            _ = try await broken.resolve(source: "tx", musicInfo: ["songmid": "TESTMID"])
            throw NSError(domain: "LXSmoke", code: 3, userInfo: [NSLocalizedDescriptionKey: "expected rejection was ignored"])
        } catch LXSourceScriptHost.HostError.initialization(let message) {
            guard message.contains("expected failure") else { throw NSError(domain: "LXSmoke", code: 4) }
        }
    }
}
