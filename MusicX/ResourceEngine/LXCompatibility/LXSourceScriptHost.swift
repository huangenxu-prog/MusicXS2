import Foundation
import JavaScriptCore

/// Experimental LX custom-source host. Not connected to the production resolver.
/// Each instance owns one JSContext; call all methods on the main thread.
@MainActor
final class LXSourceScriptHost {
    enum HostError: LocalizedError {
        case initialization(String)
        case notReady
        case invalidResponse
        case timedOut

        var errorDescription: String? {
            switch self {
            case .initialization(let message): return message
            case .notReady: return "洛雪音源尚未注册"
            case .invalidResponse: return "音源未返回有效的 HTTP 播放地址"
            case .timedOut: return "洛雪音源解析超时"
            }
        }
    }

    private let context: JSContext
    private let session: URLSession
    private(set) var registeredSources: [String: Any] = [:]
    private(set) var lastError: String?
    private var nextRequestID = 0
    private var completions: [Int: (Result<String, Error>) -> Void] = [:]

    init(script: String, session: URLSession = .shared) throws {
        guard let context = JSContext() else {
            throw HostError.initialization("无法创建 JavaScriptCore 上下文")
        }
        self.context = context
        self.session = session
        context.exceptionHandler = { [weak self] _, exception in
            self?.lastError = exception?.toString()
        }

        let network: @convention(block) (String, JSValue, JSValue) -> Void = { [weak self] url, options, callback in
            self?.performHTTP(url: url, options: options, callback: callback)
        }
        let registration: @convention(block) (String, JSValue) -> Void = { [weak self] event, payload in
            guard event == "inited" else { return }
            self?.registeredSources = payload.toDictionary()?["sources"] as? [String: Any] ?? [:]
        }
        context.setObject(unsafeBitCast(network, to: AnyObject.self), forKeyedSubscript: "__lxHTTP" as NSString)
        context.setObject(unsafeBitCast(registration, to: AnyObject.self), forKeyedSubscript: "__lxSend" as NSString)
        context.evaluateScript(Self.bootstrap)
        context.evaluateScript(script)
        if let error = lastError {
            throw HostError.initialization(error)
        }
    }

    /// Requests a URL through the LX musicUrl event. The JS promise is resolved in its own context.
    func resolve(source: String, musicInfo: [String: Any], quality: String = "320k",
                 timeout: TimeInterval = 15) async throws -> URL {
        guard registeredSources[source] != nil else { throw HostError.notReady }
        nextRequestID += 1
        let id = nextRequestID
        let urlString: String = try await withCheckedThrowingContinuation { continuation in
            completions[id] = { result in continuation.resume(with: result) }
            let payload: [String: Any] = [
                "action": "musicUrl", "source": source,
                "info": ["type": quality, "musicInfo": musicInfo]
            ]
            let json = Self.jsonString(payload)
            context.evaluateScript("__lxResolve(\(id), \(json))")
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(max(timeout, 1) * 1_000_000_000))
                self?.finish(id: id, result: .failure(HostError.timedOut))
            }
        }
        guard let url = URL(string: urlString), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else { throw HostError.invalidResponse }
        return url
    }

    private func finish(id: Int, result: Result<String, Error>) {
        guard let completion = completions.removeValue(forKey: id) else { return }
        completion(result)
    }

    private func performHTTP(url: String, options: JSValue, callback: JSValue) {
        guard let target = URL(string: url), ["https", "http"].contains(target.scheme?.lowercased() ?? ""),
              target.host != nil else {
            callback.call(withArguments: ["Invalid HTTP URL", NSNull()])
            return
        }
        let opts = options.toDictionary() ?? [:]
        var request = URLRequest(url: target)
        request.httpMethod = opts["method"] as? String ?? "GET"
        if let headers = opts["headers"] as? [String: String] {
            for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        }
        if let body = opts["body"] as? String { request.httpBody = Data(body.utf8) }
        if let timeout = opts["timeout"] as? Double {
            request.timeoutInterval = max(1, timeout / 1000)
        }
        session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error {
                    callback.call(withArguments: [error.localizedDescription, NSNull()])
                    return
                }
                let http = response as? HTTPURLResponse
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                callback.call(withArguments: [
                    NSNull(),
                    ["body": body, "statusCode": http?.statusCode ?? 0,
                     "headers": http?.allHeaderFields ?? [:]]
                ])
            }
        }.resume()
    }

    private static func jsonString(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed, .sortedKeys]),
              let result = String(data: data, encoding: .utf8) else { return "null" }
        return result
    }

    private static let bootstrap = #"""
    (function () {
      const handlers = {};
      const pending = {};
      const EVENTS = { request: 'request', inited: 'inited',
                       updateAlert: 'updateAlert' };
      globalThis.lx = {
        EVENT_NAMES: EVENTS,
        env: { platform: 'ios', version: '1.0.0' },
        on: function (event, handler) { handlers[event] = handler; },
        send: function (event, payload) { __lxSend(event, payload); },
        request: function (url, options, callback) {
          if (typeof options === 'function') { callback = options; options = {}; }
          __lxHTTP(url, options || {}, callback);
        },
        utils: {
          buffer: {
            from: function (str) { return String(str); },
            bufToString: function (buf) { return String(buf); }
          }
        }
      };
      globalThis.__lxResolve = function (id, payload) {
        const handler = handlers[EVENTS.request];
        if (!handler) { __lxComplete(id, '', 'request handler missing'); return; }
        Promise.resolve().then(function () { return handler(payload); }).then(
          function (value) { __lxComplete(id, String(value || ''), ''); },
          function (error) { __lxComplete(id, '', String(error && error.message || error)); }
        );
      };
    })();
    """#
}
