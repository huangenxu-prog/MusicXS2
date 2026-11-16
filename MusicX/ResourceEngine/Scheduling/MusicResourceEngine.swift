import Foundation

private final class ResourceProviderPerformance {
    static let shared = ResourceProviderPerformance()

    private struct Attempt: Codable {
        let succeeded: Bool
        let durationMilliseconds: Int
        let timestamp: Date
    }

    private let lock = NSLock()
    private let storageKey = "musicx.resource-provider-performance.v1"
    private var attempts: [String: [Attempt]]

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([String: [Attempt]].self, from: data) {
            attempts = saved
        } else {
            attempts = [:]
        }
    }

    func record(identifier: String, succeeded: Bool, duration: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }

        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        var recent = (attempts[identifier] ?? []).filter { $0.timestamp > cutoff }
        recent.append(Attempt(
            succeeded: succeeded,
            durationMilliseconds: max(0, Int(duration * 1_000)),
            timestamp: Date()
        ))
        attempts[identifier] = Array(recent.suffix(30))
        if let data = try? JSONEncoder().encode(attempts) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func score(identifier: String, baseline: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }

        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        let recent = (attempts[identifier] ?? []).filter { $0.timestamp > cutoff }
        guard !recent.isEmpty else { return baseline }

        let successRate = Double(recent.filter(\.succeeded).count) / Double(recent.count)
        let averageLatency = Double(recent.map(\.durationMilliseconds).reduce(0, +)) / Double(recent.count)
        return Int(successRate * 100 - min(averageLatency / 150, 30) + Double(baseline))
    }
}

/// Per-provider circuit breaker. A no-match response is healthy: it means the
/// supplier answered successfully but did not have this track.
private final class ResourceProviderCircuitBreaker {
    static let shared = ResourceProviderCircuitBreaker()

    private struct State {
        var consecutiveFailures = 0
        var openedUntil: Date?
        var halfOpenProbeInFlight = false
    }

    private let lock = NSLock()
    private var states: [String: State] = [:]
    private let failureThreshold = 3
    private let cooldown: TimeInterval = 60

    private init() {}

    func shouldAttempt(_ identifier: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard var state = states[identifier] else { return true }
        guard let openedUntil = state.openedUntil else { return true }
        guard Date() >= openedUntil else { return false }
        guard !state.halfOpenProbeInFlight else { return false }

        state.halfOpenProbeInFlight = true
        states[identifier] = state
        return true
    }

    func recordHealthy(_ identifier: String) {
        lock.lock()
        states[identifier] = State()
        lock.unlock()
    }

    func recordFailure(_ identifier: String) {
        lock.lock()
        defer { lock.unlock() }

        var state = states[identifier] ?? State()
        if state.openedUntil != nil && state.halfOpenProbeInFlight {
            state.consecutiveFailures = failureThreshold
        } else {
            state.consecutiveFailures += 1
        }
        state.halfOpenProbeInFlight = false
        if state.consecutiveFailures >= failureThreshold {
            state.openedUntil = Date().addingTimeInterval(cooldown)
        }
        states[identifier] = state
    }

    /// A single song's URL may be expired, region-blocked, or unavailable even
    /// while the provider itself is healthy. Release a half-open probe slot
    /// without counting that resource-specific failure against the provider.
    func recordResourceFailure(_ identifier: String) {
        lock.lock()
        defer { lock.unlock() }
        guard var state = states[identifier], state.halfOpenProbeInFlight else { return }
        state.halfOpenProbeInFlight = false
        states[identifier] = state
    }
}

/// Cross-platform fallback is isolated from the source-native providers.
/// It searches by title and artist and resolves using the matched platform's own ID.
private struct CrossPlatformFallbackProvider: MusicResourceProvider {
    let identifier = "cross-platform-matched-fallback"
    let displayName = "跨平台匹配备用音源"
    let session: URLSession
    let excludedURLIDs: Set<String>

    func resolve(song: MusicSong, quality: MusicQuality) async throws -> ResolvedMusicResource? {
        guard let url = try await LXMusicURLResolver(session: session)
            .resolveCrossPlatformFallback(song: song, quality: quality, excludedURLIDs: excludedURLIDs) else {
            return nil
        }
        return ResolvedMusicResource(url: url, providerID: LXMusicURLResolver.fallbackURLID(url), providerName: displayName)
    }
}

/// Resolve a track through every imported LX script that advertises its platform.
/// The script library remains user-managed; importing or removing scripts requires no rebuild.
private struct ImportedLXSourceProvider: MusicResourceProvider {
    let identifier = "imported-lx-scripts"
    let displayName = "已导入洛雪音源"
    let excludedScriptIDs: Set<String>
    let excludedURLIDs: Set<String>

    func resolve(song: MusicSong, quality: MusicQuality) async throws -> ResolvedMusicResource? {
        let platform: String
        switch song.source {
        case .qq: platform = "tx"
        case .netease: platform = "wy"
        case .kuwo: platform = "kw"
        case .kugou: platform = "kg"
        default: return nil
        }

        let scripts = try await MainActor.run { () throws -> [(String, String)] in
            var scripts: [(String, String)] = []
            if let url = Bundle.main.url(forResource: "BundledLXSources", withExtension: "json"),
               let data = try? Data(contentsOf: url),
               let bundled = try? JSONDecoder().decode([BundledLXScript].self, from: data) {
                scripts = bundled.map { ($0.id, $0.contents) }
            }
            // Only scripts whose preview actually started playback are approved.
            // Re-read on every resolution so imports and deletions take effect without rebuilding.
            if let library = try? LXSourceLibrary() {
                for id in library.approvedIDs.sorted() {
                    if let script = try? library.load(id: id) {
                        scripts.append((id, script))
                    }
                }
            }
            return scripts
        }
        guard !scripts.isEmpty else {
            MusicSourceDiagnostics.shared.record(
                event: "lx-imported-inventory", source: song.source.rawValue,
                provider: identifier, duration: 0, result: "empty",
                detail: "No imported JS files in this app's ApplicationSupport/LXCustomSources"
            )
            return nil
        }
        MusicSourceDiagnostics.shared.record(
            event: "lx-imported-inventory", source: song.source.rawValue,
            provider: identifier, duration: 0, result: "loaded",
            detail: "scripts=\(scripts.count); platform=\(platform); track_id_present=\(!song.sourceID.isEmpty)"
        )

        // Each JSContext is confined to the main actor. Network callbacks can
        // complete independently; the first valid URL wins and remaining tasks
        // are cancelled. Script failures never disable other imported sources.
        return try await withThrowingTaskGroup(of: ResolvedMusicResource?.self) { group in
            for (id, script) in scripts {
                guard !excludedScriptIDs.contains("lx:\(id):\(platform)") else { continue }
                group.addTask { @MainActor in
                    do {
                        try Task.checkCancellation()
                        let host = try LXSourceScriptHost(script: script)
                        let ready = await host.awaitRegistration(timeout: 8)
                        guard ready else {
                            MusicSourceDiagnostics.shared.record(
                                event: "lx-imported-registration", source: song.source.rawValue,
                                provider: "lx:\(id):\(platform)", duration: 0,
                                result: "not_ready",
                                detail: "js_error=\(host.lastError ?? "none")"
                            )
                            return nil
                        }
                        guard let metadata = host.registeredSources[platform] as? [String: Any] else {
                            MusicSourceDiagnostics.shared.record(
                                event: "lx-imported-registration", source: song.source.rawValue,
                                provider: "lx:\(id):\(platform)", duration: 0,
                                result: "unsupported_platform",
                                detail: "registered=\(host.registeredSources.keys.sorted().joined(separator: ","))"
                            )
                            return nil
                        }
                        MusicSourceDiagnostics.shared.record(
                            event: "lx-imported-registration", source: song.source.rawValue,
                            provider: "lx:\(id):\(platform)", duration: 0,
                            result: "supported",
                            detail: "qualities=\((metadata["qualitys"] as? [String] ?? []).joined(separator: ","))"
                        )
                        let qualities = metadata["qualitys"] as? [String] ?? []
                        let requested = qualities.contains("320k") ? "320k"
                            : (qualities.contains("128k") ? "128k" : (qualities.first ?? "320k"))
                        let info: [String: Any] = [
                            "songmid": song.sourceID,
                            "id": song.sourceID,
                            "name": song.title,
                            "singer": song.artist,
                            "albumName": song.album ?? "",
                            "interval": Int(song.duration ?? 0),
                            "hash": song.hash ?? song.sourceID,
                            "albumId": song.albumID ?? ""
                        ]
                        let url = try await host.resolve(
                            source: platform, musicInfo: info, quality: requested, timeout: 15
                        )
                        try Task.checkCancellation()
                        guard !excludedURLIDs.contains(LXMusicURLResolver.fallbackURLID(url)) else {
                            return nil
                        }
                        return ResolvedMusicResource(
                            url: url, providerID: "lx:\(id):\(platform)",
                            providerName: "洛雪导入音源"
                        )
                    } catch {
                        if Task.isCancelled || error is CancellationError { return nil }
                        MusicSourceDiagnostics.shared.record(
                            event: "lx-imported-resolve", source: song.source.rawValue,
                            provider: "lx:\(id):\(platform)", duration: 0,
                            result: "failed", detail: error.localizedDescription
                        )
                        return nil
                    }
                }
            }
            while let candidate = try await group.next() {
                if let candidate {
                    group.cancelAll()
                    return candidate
                }
            }
            return nil
        }
    }
}

private struct BundledLXScript: Decodable {
    let id: String
    let contents: String
}

/// The middle layer between the player-facing resolver and external supplier libraries.
/// It intentionally does not own playback URL caching; MusicCache remains in the
/// existing LXMusicURLResolver compatibility boundary.
struct MusicResourceEngine {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Resolve imported LX scripts for a matched track on its OWN platform.
    /// Used by cross-platform fallback; never re-enters the resource scheduler.
    func resolveImportedLX(song: MusicSong, quality: MusicQuality, excludedURLIDs: Set<String> = []) async throws -> URL? {
        try await ImportedLXSourceProvider(excludedScriptIDs: [], excludedURLIDs: excludedURLIDs)
            .resolve(song: song, quality: quality)?.url
    }

    /// Native NetEase and pyncmd are independent cross-platform candidates.
    /// Never call the full scheduler here: it would recurse into fallback.
    func resolveMatchedNetEase(song: MusicSong, quality: MusicQuality, excludedURLIDs: Set<String> = []) async -> URL? {
        guard song.source == .netease else { return nil }
        return await withTaskGroup(of: URL?.self, returning: URL?.self) { group in
            group.addTask {
                try? await NetEaseNativeAudioProvider(session: session)
                    .resolve(song: song, quality: quality)?.url
            }
            group.addTask {
                try? await KumonePyncmdAudioSourceProvider()
                    .resolve(song: song, quality: quality)?.url
            }
            while let url = await group.next() {
                if let url, !excludedURLIDs.contains(LXMusicURLResolver.fallbackURLID(url)) {
                    group.cancelAll()
                    return url
                }
            }
            return nil
        }
    }

    func resolve(song: MusicSong, quality: MusicQuality) async throws -> URL {
        let resource = try await resolveResource(song: song, quality: quality)
        return resource.url
    }

    /// Resolve a resource while excluding providers whose last returned stream
    /// was rejected by AVPlayer for this same track.
    func resolveResource(
        song: MusicSong,
        quality: MusicQuality,
        excludingProviderIDs: Set<String> = []
    ) async throws -> ResolvedMusicResource {
        // First try the source's existing direct URL. If it is unavailable,
        // race the dynamic imported-LX and matched-catalog fallback paths.
        // Never wait for all fallback suppliers once a candidate is available.
        let directProviders: [any MusicResourceProvider]
        switch song.source {
        case .netease:
            directProviders = [NetEaseNativeAudioProvider(session: session)]
        case .qq:
            // These are existing direct-URL adapters, not official QQ APIs.
            directProviders = [QQChkszAudioProvider(session: session)]
        default:
            directProviders = []
        }
        for provider in directProviders where !excludingProviderIDs.contains(provider.identifier) {
            if let resource = try? await provider.resolve(song: song, quality: quality),
               Self.isValidStreamURL(resource.url) {
                return resource
            }
        }

        let providers: [any MusicResourceProvider]
        switch song.source {
        case .netease:
            providers = [
                KumonePyncmdAudioSourceProvider(),
                ImportedLXSourceProvider(excludedScriptIDs: excludingProviderIDs, excludedURLIDs: excludingProviderIDs),
                CrossPlatformFallbackProvider(session: session, excludedURLIDs: excludingProviderIDs)
            ]
        default:
            providers = [
                ImportedLXSourceProvider(excludedScriptIDs: excludingProviderIDs, excludedURLIDs: excludingProviderIDs),
                CrossPlatformFallbackProvider(session: session, excludedURLIDs: excludingProviderIDs)
            ]
        }

        return try await withThrowingTaskGroup(
            of: (ResolvedMusicResource?, String?).self,
            returning: ResolvedMusicResource.self
        ) { group in
            for provider in providers {
                group.addTask {
                    try Task.checkCancellation()
                    if excludingProviderIDs.contains(provider.identifier) {
                        return (nil, "\(provider.displayName)：上一次播放失败，已跳过")
                    }
                    guard ResourceProviderCircuitBreaker.shared.shouldAttempt(provider.identifier) else {
                        return (nil, "\(provider.displayName)：暂时冷却")
                    }
                    let startedAt = Date()
                    do {
                        guard let resource = try await provider.resolve(song: song, quality: quality) else {
                            ResourceProviderCircuitBreaker.shared.recordHealthy(provider.identifier)
                            MusicSourceDiagnostics.shared.record(
                                event: "resource-provider", source: song.source.rawValue,
                                provider: provider.identifier,
                                duration: Date().timeIntervalSince(startedAt), result: "no_match"
                            )
                            return (nil, "\(provider.displayName)：没有可用资源")
                        }
                        try Task.checkCancellation()
                        guard Self.isValidStreamURL(resource.url) else {
                            throw MusicSourceError.invalidResponse("供应商返回了无效播放地址")
                        }
                        let elapsed = Date().timeIntervalSince(startedAt)
                        ResourceProviderCircuitBreaker.shared.recordHealthy(provider.identifier)
                        ResourceProviderPerformance.shared.record(
                            identifier: provider.identifier, succeeded: true, duration: elapsed
                        )
                        MusicSourceDiagnostics.shared.record(
                            event: "resource-provider", source: song.source.rawValue,
                            provider: resource.providerID, duration: elapsed,
                            result: "url_returned_direct"
                        )
                        return (resource, nil)
                    } catch {
                        if Task.isCancelled || error is CancellationError
                            || (error as? URLError)?.code == .cancelled {
                            throw CancellationError()
                        }
                        let elapsed = Date().timeIntervalSince(startedAt)
                        if Self.shouldTripCircuitBreaker(for: error) {
                            ResourceProviderCircuitBreaker.shared.recordFailure(provider.identifier)
                            ResourceProviderPerformance.shared.record(
                                identifier: provider.identifier, succeeded: false, duration: elapsed
                            )
                        } else {
                            ResourceProviderCircuitBreaker.shared.recordResourceFailure(provider.identifier)
                        }
                        MusicSourceDiagnostics.shared.record(
                            event: "resource-provider", source: song.source.rawValue,
                            provider: provider.identifier, duration: elapsed,
                            result: "resource_unavailable", detail: error.localizedDescription
                        )
                        return (nil, "\(provider.displayName)：\(error.localizedDescription)")
                    }
                }
            }
            var failures: [String] = []
            while let (resource, failure) = try await group.next() {
                if let resource {
                    group.cancelAll()
                    return resource
                }
                if let failure { failures.append(failure) }
            }
            throw MusicSourceError.noPlayableURL(
                source: song.source,
                details: failures.isEmpty ? "所有并发解析通道均未返回可用地址"
                    : failures.joined(separator: "；")
            )
        }
    }

    /// HTTP 4xx responses from a stream URL are usually song-, region-, or
    /// entitlement-specific. They should trigger fallback for this track, but
    /// must not disable the whole provider for unrelated tracks.
    private static func shouldTripCircuitBreaker(for error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled:
                return false
            case .timedOut, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
                 .networkConnectionLost, .notConnectedToInternet, .secureConnectionFailed,
                 .cannotLoadFromNetwork:
                return true
            default:
                break
            }
        }

        let message = error.localizedDescription.lowercased()
        if let marker = message.range(of: "http ") {
            let statusText = message[marker.upperBound...].prefix(3)
            if let status = Int(statusText), (400..<500).contains(status), status != 429 {
                return false
            }
        }
        if message.contains("播放地址返回了 html/json")
            || message.contains("播放地址返回了非音频内容")
            || message.contains("播放流响应为空") {
            return false
        }
        return true
    }


    private static func isValidStreamURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              components.user == nil,
              components.password == nil,
              !url.absoluteString.contains(where: { $0.isWhitespace }) else {
            return false
        }
        return true
    }
}
