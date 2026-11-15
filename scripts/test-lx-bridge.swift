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

        // Verify common LX crypto and binary helpers required by Flower/Grass.
        let helpers = try LXSourceScriptHost(script: """
        const lx = globalThis.lx;
        if (lx.utils.crypto.md5('abc') !== '900150983cd24fb0d6963f7d28e17f72') throw new Error('MD5 mismatch');
        if (lx.utils.buffer.bufToString(lx.utils.buffer.from('6869', 'hex')) !== 'hi') throw new Error('hex buffer mismatch');
        if (!lx.currentScriptInfo.version || !lx.version) throw new Error('script metadata missing');
        lx.on(lx.EVENT_NAMES.request, () => 'https://example.com/helper-test.mp3');
        lx.send(lx.EVENT_NAMES.inited, { sources: { tx: {} } });
        """)
        guard helpers.registeredSources["tx"] != nil else {
            throw NSError(domain: "LXSmoke", code: 8, userInfo: [NSLocalizedDescriptionKey: "helper script failed to register"])
        }

        // Exercise the exact user-supplied Xinghai script with deterministic mocked HTTP.
        let fixtureURL = URL(fileURLWithPath: "scripts/fixtures/xinghai-v3.2.19.js")
        let fixture = try String(contentsOf: fixtureURL, encoding: .utf8)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LXMockURLProtocol.self]
        let session = URLSession(configuration: config)
        LXMockURLProtocol.reset()
        let xinghai = try LXSourceScriptHost(script: fixture, session: session)
        guard xinghai.registeredSources["tx"] != nil else {
            throw NSError(domain: "LXSmoke", code: 5, userInfo: [NSLocalizedDescriptionKey: "Xinghai QQ registration missing"])
        }
        let xinghaiURL = try await xinghai.resolve(
            source: "tx",
            musicInfo: ["songmid": "TESTMID", "name": "Test Song", "singer": "Test Singer"],
            quality: "320k",
            timeout: 8
        )
        guard LXMockURLProtocol.receivedTokenRequest, LXMockURLProtocol.receivedAuthorizedQQRequest else {
            throw NSError(domain: "LXSmoke", code: 7, userInfo: [NSLocalizedDescriptionKey: "Xinghai token or authenticated QQ request missing"])
        }
        guard xinghaiURL.absoluteString == "https://example.com/xinghai-test.mp3" else {
            throw NSError(domain: "LXSmoke", code: 6, userInfo: [NSLocalizedDescriptionKey: "Xinghai mock URL mismatch"])
        }

    }
}

final class LXMockURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var tokenRequest = false
    private static var authorizedQQRequest = false
    static var receivedTokenRequest: Bool { lock.lock(); defer { lock.unlock() }; return tokenRequest }
    static var receivedAuthorizedQQRequest: Bool { lock.lock(); defer { lock.unlock() }; return authorizedQQRequest }
    static func reset() { lock.lock(); defer { lock.unlock() }; tokenRequest = false; authorizedQQRequest = false }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let path = url.path
        let json: String
        if path.hasSuffix("/token.php") {
            Self.lock.lock(); Self.tokenRequest = true; Self.lock.unlock()
            json = #"{"data":{"token":"xh3.test-token"}}"#
        } else if path == "/lx/api/" || path == "/lx/api" {
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let isQQ = query.contains { $0.name == "source" && $0.value == "qq" }
            let isSong = query.contains { $0.name == "songmid" && $0.value == "TESTMID" }
            let token = request.value(forHTTPHeaderField: "X-Token")
            Self.lock.lock(); Self.authorizedQQRequest = isQQ && isSong && token == "xh3.test-token"; Self.lock.unlock()
            json = #"{"code":200,"url":"https://example.com/xinghai-test.mp3"}"#
        } else if path == "/ip.php" {
            json = #"{"ip":"127.0.0.1"}"#
        } else {
            json = #"{}"#
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
