import Foundation
import JavaScriptCore
import CryptoKit
import CommonCrypto

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
    private(set) var initializationEvents: [String] = []
    private(set) var didReceiveInitialization = false
    private var nextRequestID = 0
    // JSValue callbacks must remain strongly rooted until URLSession completes.
    private var nextHTTPID = 0
    private var pendingHTTPCallbacks: [Int: JSValue] = [:]
    private var pendingHTTPTasks: [Int: URLSessionDataTask] = [:]
    private var nextTimerID = 0
    private var pendingTimers: [Int: (callback: JSValue, task: Task<Void, Never>)] = [:]
    private var completions: [Int: (Result<String, Error>) -> Void] = [:]
    private var timeoutTasks: [Int: Task<Void, Never>] = [:]

    init(script: String, session: URLSession = .shared) throws {
        guard let context = JSContext() else {
            throw HostError.initialization("无法创建 JavaScriptCore 上下文")
        }
        self.context = context
        self.session = session
        context.exceptionHandler = { [weak self] _, exception in
            self?.lastError = exception?.toString()
            self?.initializationEvents.append("JS exception: \(exception?.toString() ?? "unknown")")
        }

        let network: @convention(block) (String, JSValue, JSValue) -> Int = { [weak self] url, options, callback in
            self?.performHTTP(url: url, options: options, callback: callback) ?? -1
        }
        let cancelHTTP: @convention(block) (Int) -> Void = { [weak self] id in
            self?.cancelHTTP(id: id)
        }
        let registration: @convention(block) (String, JSValue) -> Void = { [weak self] event, payload in
            self?.initializationEvents.append("event: \(event)")
            guard event == "inited" else { return }
            self?.didReceiveInitialization = true
            let sources = payload.toDictionary()?["sources"] as? [String: Any] ?? [:]
            self?.registeredSources = sources
            let platforms = sources.keys.sorted().joined(separator: ",")
            self?.initializationEvents.append("registered platforms: \(platforms.isEmpty ? "none" : platforms)")
        }
        let complete: @convention(block) (Int, String, String) -> Void = { [weak self] id, value, error in
            if !error.isEmpty { self?.finish(id: id, result: .failure(HostError.initialization(error))) }
            else { self?.finish(id: id, result: .success(value)) }
        }
        let md5: @convention(block) (String) -> String = { input in
            Insecure.MD5.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
        }
        // LX scripts may verify their own raw source against server-provided MD5.
        // The metadata must describe the actual imported JS, not a placeholder.
        let versionPattern = #"@version\s+([^\s*]+)"#
        let scriptVersion: String
        if let range = script.range(of: versionPattern, options: .regularExpression) {
            scriptVersion = script[range].split(whereSeparator: { $0.isWhitespace }).last.map(String.init) ?? "1"
        } else {
            scriptVersion = "1"
        }
        context.setObject(script, forKeyedSubscript: "__lxRawScript" as NSString)
        context.setObject(scriptVersion, forKeyedSubscript: "__lxScriptVersion" as NSString)
        context.setObject(md5, forKeyedSubscript: "__lxMD5" as NSString)
        // LX crypto.aesEncrypt(data, mode, key, iv) returns a byte buffer.
        // Return hex from the native bridge, then expose bytes to JS scripts.
        let encryptAES: @convention(block) (String, String, String, String) -> String = { data, mode, key, iv in
            Self.aesEncryptHex(data: data, mode: mode, key: key, iv: iv) ?? ""
        }
        context.setObject(encryptAES, forKeyedSubscript: "__lxAES" as NSString)
        let scheduleTimer: @convention(block) (JSValue, Double) -> Int = { [weak self] callback, delay in
            guard let self else { return -1 }
            self.nextTimerID += 1
            let timerID = self.nextTimerID
            let milliseconds = min(max(delay.isFinite ? delay : 0, 0), 60_000)
            let task = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .milliseconds(Int(milliseconds))) }
                catch { return }
                guard let self, let entry = self.pendingTimers.removeValue(forKey: timerID) else { return }
                entry.callback.call(withArguments: [])
            }
            self.pendingTimers[timerID] = (callback, task)
            return timerID
        }
        let cancelTimer: @convention(block) (Int) -> Void = { [weak self] id in
            self?.pendingTimers.removeValue(forKey: id)?.task.cancel()
        }
        context.setObject(scheduleTimer, forKeyedSubscript: "__lxSetTimeout" as NSString)
        context.setObject(cancelTimer, forKeyedSubscript: "__lxClearTimeout" as NSString)
        context.setObject(network, forKeyedSubscript: "__lxHTTP" as NSString)
        context.setObject(cancelHTTP, forKeyedSubscript: "__lxCancelHTTP" as NSString)
        context.setObject(complete, forKeyedSubscript: "__lxComplete" as NSString)
        context.setObject(registration, forKeyedSubscript: "__lxSend" as NSString)
        let log: @convention(block) (String, String) -> Void = { [weak self] level, message in
            guard let self else { return }
            self.initializationEvents.append("console.\(level): \(String(message.prefix(400)))")
            if self.initializationEvents.count > 120 {
                self.initializationEvents.removeFirst(self.initializationEvents.count - 120)
            }
        }
        context.setObject(log, forKeyedSubscript: "__lxLog" as NSString)
        context.evaluateScript(Self.bootstrap)
        guard context.evaluateScript("typeof setTimeout === 'function' && typeof clearTimeout === 'function'")?.toBool() == true else {
            throw HostError.initialization("LX timer preflight failed: \(lastError ?? "no JS exception")")
        }
        initializationEvents.append("timer preflight OK")
        context.evaluateScript(script)
        initializationEvents.append("timer postload: \(context.evaluateScript("typeof setTimeout + '/' + typeof clearTimeout")?.toString() ?? "unknown")")
        if let error = lastError {
            throw HostError.initialization(error)
        }
    }

    /// Wait for scripts that register after asynchronous setup or HTTP callbacks.
    func awaitRegistration(timeout: TimeInterval = 8) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !didReceiveInitialization && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(200))
            if Task.isCancelled { break }
        }
        return !registeredSources.isEmpty
    }

    /// Requests a URL through the LX musicUrl event. The JS promise is resolved in its own context.
    func resolve(source: String, musicInfo: [String: Any], quality: String = "320k",
                 timeout: TimeInterval = 15) async throws -> URL {
        guard registeredSources[source] != nil else { throw HostError.notReady }
        let timerStatus = context.evaluateScript("typeof setTimeout + '/' + typeof clearTimeout")?.toString() ?? "unknown"
        initializationEvents.append("timer before resolve: \(timerStatus)")
        guard timerStatus == "function/function" else {
            throw HostError.initialization("JS timer unavailable before resolve: \(timerStatus)")
        }
        nextRequestID += 1
        let id = nextRequestID
        let urlString: String = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                completions[id] = { result in continuation.resume(with: result) }
                // Cancellation may have happened before the continuation was installed.
                if Task.isCancelled {
                    finish(id: id, result: .failure(CancellationError()))
                    return
                }
                let payload: [String: Any] = [
                    "action": "musicUrl", "source": source,
                    "info": ["type": quality, "musicInfo": musicInfo]
                ]
                let json = Self.jsonString(payload)
                context.evaluateScript("__lxResolve(\(id), \(json))")
                timeoutTasks[id] = Task { @MainActor [weak self] in
                    do { try await Task.sleep(nanoseconds: UInt64(max(timeout, 1) * 1_000_000_000)) }
                    catch { return }
                    self?.finish(id: id, result: .failure(HostError.timedOut))
                }
            }
        } onCancel: {
            // Cancelled competitors must release their continuations immediately,
            // rather than keeping the task group alive for the full 15-second timeout.
            Task { @MainActor [weak self] in
                self?.finish(id: id, result: .failure(CancellationError()))
            }
        }
        guard let url = URL(string: urlString), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else { throw HostError.invalidResponse }
        return url
    }

    private func finish(id: Int, result: Result<String, Error>) {
        guard let completion = completions.removeValue(forKey: id) else { return }
        timeoutTasks.removeValue(forKey: id)?.cancel()
        completion(result)
    }

    @discardableResult
    private func performHTTP(url: String, options: JSValue, callback: JSValue) -> Int {
        nextHTTPID += 1
        let requestID = nextHTTPID
        // JSCore may collect an asynchronously captured JS function unless
        // the owning host keeps a strong JSValue reference.
        pendingHTTPCallbacks[requestID] = callback
        guard let target = URL(string: url),
              ["https", "http"].contains(target.scheme?.lowercased() ?? ""),
              target.host != nil else {
            finishHTTP(id: requestID, error: "Invalid HTTP URL", response: nil)
            return requestID
        }
        let opts = options.toDictionary() ?? [:]
        var request = URLRequest(url: target)
        request.httpMethod = opts["method"] as? String ?? "GET"
        if let headers = opts["headers"] as? [String: Any] {
            for (key, value) in headers {
                request.setValue(String(describing: value), forHTTPHeaderField: key)
            }
        }
        if let body = opts["body"] as? String {
            request.httpBody = Data(body.utf8)
        } else if let body = opts["body"],
                  JSONSerialization.isValidJSONObject(body),
                  let encoded = try? JSONSerialization.data(withJSONObject: body) {
            // LX scripts may pass a plain object as POST body. Previously this
            // produced an empty request, causing API-specific false failures.
            request.httpBody = encoded
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }
        if let timeout = opts["timeout"] as? NSNumber {
            request.timeoutInterval = max(1, timeout.doubleValue / 1000)
        }
        initializationEvents.append("HTTP start #\(requestID) \(target.host ?? "unknown")")
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let error {
                    let nsError = error as NSError
                    let detail = "\(error.localizedDescription) [domain=\(nsError.domain), code=\(nsError.code), host=\(target.host ?? "unknown")]"
                    self.finishHTTP(id: requestID, error: detail, response: nil)
                    return
                }
                let http = response as? HTTPURLResponse
                let raw = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let body: Any
                // LX request returns a decoded object for JSON response bodies.
                // Preserve plain text for endpoints that do not return JSON.
                if let data, let parsed = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
                    body = parsed
                } else {
                    body = raw
                }
                if let host = target.host, host == "registry.npmjs.org" || host == "registry.npmmirror.com" {
                    if let dictionary = body as? [String: Any] {
                        let keys = dictionary.keys.sorted().prefix(20).joined(separator: ",")
                        let version = dictionary["version"] as? String ?? "unknown"
                        let code = dictionary["code"].map { String(describing: $0) } ?? "none"
                        self.initializationEvents.append("config #\(requestID): keys=[\(keys)], version=\(version), code=\(code)")
                    } else {
                        self.initializationEvents.append("config #\(requestID): non-object body, bytes=\(data?.count ?? 0)")
                    }
                }
                self.finishHTTP(id: requestID, error: nil, response: [
                    "body": body,
                    "statusCode": http?.statusCode ?? 0,
                    "statusMessage": HTTPURLResponse.localizedString(forStatusCode: http?.statusCode ?? 0),
                    "headers": http?.allHeaderFields ?? [:]
                ])
            }
        }
        pendingHTTPTasks[requestID] = task
        task.resume()
        return requestID
    }

    private func cancelHTTP(id: Int) {
        // Cancellation is a normal outcome when a faster source wins. Do not
        // invoke the JS callback after cancellation; the caller has settled.
        pendingHTTPCallbacks.removeValue(forKey: id)
        pendingHTTPTasks.removeValue(forKey: id)?.cancel()
    }

    private func finishHTTP(id: Int, error: String?, response: [String: Any]?) {
        pendingHTTPTasks.removeValue(forKey: id)
        guard let callback = pendingHTTPCallbacks.removeValue(forKey: id) else { return }
        if let error {
            initializationEvents.append("HTTP error #\(id): \(error)")
            callback.call(withArguments: [error, NSNull(), NSNull()])
        } else {
            let status = response?["statusCode"] as? Int ?? 0
            initializationEvents.append("HTTP complete #\(id): \(status)")
            callback.call(withArguments: [NSNull(), response ?? [:], response?["body"] ?? NSNull()])
        }
    }

    private static func aesEncryptHex(data: String, mode: String, key: String, iv: String) -> String? {
        let normalizedMode = mode.lowercased()
        let ecb = normalizedMode == "ecb" || normalizedMode.hasSuffix("-ecb")
        let cbc = normalizedMode == "cbc" || normalizedMode.hasSuffix("-cbc")
        guard ecb || cbc else { return nil }

        let keyData = Data(key.utf8)
        guard [kCCKeySizeAES128, kCCKeySizeAES192, kCCKeySizeAES256].contains(keyData.count) else {
            return nil
        }
        let ivData = Data(iv.utf8)
        if cbc && ivData.count != kCCBlockSizeAES128 { return nil }

        let payload = Data(data.utf8)
        var output = Data(count: payload.count + kCCBlockSizeAES128)
        var outputLength: size_t = 0
        let options = CCOptions(kCCOptionPKCS7Padding | (ecb ? kCCOptionECBMode : 0))
        let status: CCCryptorStatus = output.withUnsafeMutableBytes { outputBytes in
            payload.withUnsafeBytes { inputBytes in
                keyData.withUnsafeBytes { keyBytes in
                    ivData.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES),
                            options, keyBytes.baseAddress, keyData.count,
                            ecb ? nil : ivBytes.baseAddress,
                            inputBytes.baseAddress, payload.count,
                            outputBytes.baseAddress, output.count,
                            &outputLength
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        return output.prefix(outputLength).map { String(format: "%02x", $0) }.joined()
    }

    private static func jsonString(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed, .sortedKeys]),
              let result = String(data: data, encoding: .utf8) else { return "null" }
        return result
    }

    private static let bootstrap = #"""
    (function () {
      const handlers = {};
      // Community LX scripts commonly use console.error and inspect err.message.
      // JSContext has no browser console; expose bounded diagnostics instead.
      globalThis.console = {
        log: function () { __lxLog('log', Array.from(arguments).map(String).join(' ')); },
        warn: function () { __lxLog('warn', Array.from(arguments).map(String).join(' ')); },
        error: function () { __lxLog('error', Array.from(arguments).map(String).join(' ')); },
        info: function () { __lxLog('info', Array.from(arguments).map(String).join(' ')); }
      };
      globalThis.setTimeout = function (callback, delay) {
        if (typeof callback !== 'function') throw new TypeError('setTimeout callback must be a function');
        return __lxSetTimeout(callback, Number(delay) || 0);
      };
      globalThis.clearTimeout = function (id) { __lxClearTimeout(Number(id) || 0); };
      const EVENTS = { request: 'request', inited: 'inited',
                       updateAlert: 'updateAlert' };
      globalThis.lx = {
        EVENT_NAMES: EVENTS,
        env: 'ios',
        version: '2.0.0',
        currentScriptInfo: { version: __lxScriptVersion, name: 'LX custom source', rawScript: __lxRawScript },
        on: function (event, handler) { handlers[event] = handler; },
        send: function (event, payload) { __lxSend(event, payload); },
        request: function (url, options, callback) {
          if (typeof options === 'function') { callback = options; options = {}; }
          if (typeof callback !== "function") throw new Error("lx.request requires callback");
          const id = __lxHTTP(url, options || {}, function (err, response, body) {
            // The LX callback contract expects a JS Error, not a native string.
            // Preserve the original details for scripts reading error.message.
            if (err != null && err !== '') {
              callback(err instanceof Error ? err : new Error(String(err)), response, body);
            } else {
              callback(null, response, body);
            }
          });
          return function () { __lxCancelHTTP(id); };
        },
        utils: {
          crypto: {
            md5: function (value) { return __lxMD5(String(value)); },
            aesEncrypt: function (data, mode, key, iv) {
              const hex = __lxAES(String(data), String(mode), String(key), String(iv || ''));
              if (!hex) throw new Error('Unsupported AES mode or key/IV length');
              const bytes = [];
              for (let i = 0; i < hex.length; i += 2) bytes.push(parseInt(hex.slice(i, i + 2), 16));
              return bytes;
            }
          },
          buffer: {
            from: function (value, encoding) {
              if (encoding === 'hex') {
                const hex = String(value).replace(/[^0-9a-f]/gi, '');
                const out = [];
                for (let i = 0; i + 1 < hex.length; i += 2) out.push(parseInt(hex.slice(i, i + 2), 16));
                return out;
              }
              if (Array.isArray(value)) return value;
              return Array.from(unescape(encodeURIComponent(String(value))), c => c.charCodeAt(0));
            },
            bufToString: function (buf, encoding) {
              if (encoding === 'hex') return Array.from(buf, n => Number(n).toString(16).padStart(2, '0')).join('');
              if (Array.isArray(buf)) return decodeURIComponent(escape(String.fromCharCode.apply(null, buf)));
              return String(buf);
            }
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
