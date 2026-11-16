import Foundation

struct GDStudioMetadataService {
    private struct CachedLyrics: Codable {
        let original: String
        let translated: String?
    }

    private let session: URLSession
    private let endpoint = "https://music-api.gdstudio.xyz/api.php"

    init(session: URLSession = .shared) {
        self.session = session
    }

    func artworkURL(for song: MusicSong, size: Int = 500) async throws -> URL? {
        guard let pictureID = song.pictureID, !pictureID.isEmpty else { return nil }
        let cacheKey = "artwork-url|\(song.source.rawValue)|\(pictureID)|\(size)"
        if let cached: URL = await MusicCache.shared.value(for: cacheKey) { return cached }
        let object = try await request([
            URLQueryItem(name: "types", value: "pic"),
            URLQueryItem(name: "source", value: sourceName(song.source)),
            URLQueryItem(name: "id", value: pictureID),
            URLQueryItem(name: "size", value: String(size))
        ])
        let result = extractURL(object, key: "url")
        if let result { await MusicCache.shared.insert(result, for: cacheKey, ttl: 7 * 24 * 60 * 60) }
        return result
    }

    func lyrics(for song: MusicSong) async throws -> (original: String, translated: String?)? {
        let lyricID = song.source == .qq ? song.sourceID : (song.lyricID ?? song.sourceID)
        guard !lyricID.isEmpty else { return nil }
        let cacheKey = "lyrics-v2|\(song.source.rawValue)|\(lyricID)"
        if let cached: CachedLyrics = await MusicCache.shared.value(for: cacheKey) {
            return (cached.original, cached.translated)
        }
        if song.source == .qq {
            let started = Date()
            do {
                if let native = try await qqLyrics(songID: lyricID) {
                    await MusicCache.shared.insert(
                        CachedLyrics(original: native.original, translated: native.translated),
                        for: cacheKey, ttl: 7 * 24 * 60 * 60
                    )
                    MusicSourceDiagnostics.shared.record(
                        event: "lyrics", source: song.source.rawValue,
                        provider: "qq-native-lyrics", duration: Date().timeIntervalSince(started),
                        result: "success", detail: "song_id=\(lyricID)"
                    )
                    return native
                }
                MusicSourceDiagnostics.shared.record(
                    event: "lyrics", source: song.source.rawValue,
                    provider: "qq-native-lyrics", duration: Date().timeIntervalSince(started),
                    result: "empty", detail: "song_id=\(lyricID)"
                )
            } catch {
                if Task.isCancelled || error is CancellationError
                    || (error as? URLError)?.code == .cancelled { throw CancellationError() }
                MusicSourceDiagnostics.shared.record(
                    event: "lyrics", source: song.source.rawValue,
                    provider: "qq-native-lyrics", duration: Date().timeIntervalSince(started),
                    result: "failed", detail: error.localizedDescription
                )
            }
        }
        if song.source == .netease {
            do {
                if let native = try await NetEaseNativeAPIClient(session: session).lyrics(songID: lyricID) {
                    await MusicCache.shared.insert(
                        CachedLyrics(original: native.original, translated: native.translated),
                        for: cacheKey,
                        ttl: 7 * 24 * 60 * 60
                    )
                    return native
                }
            } catch {
                if Task.isCancelled || error is CancellationError
                    || (error as? URLError)?.code == .cancelled {
                    throw CancellationError()
                }
                MusicSourceDiagnostics.shared.record(
                    event: "lyrics-fallback",
                    source: song.source.rawValue,
                    provider: "netease-native-eapi",
                    duration: 0,
                    result: "fallback_to_gdstudio",
                    detail: error.localizedDescription
                )
            }
        }
        let object = try await request([
            URLQueryItem(name: "types", value: "lyric"),
            URLQueryItem(name: "source", value: sourceName(song.source)),
            URLQueryItem(name: "id", value: lyricID)
        ])
        guard let dictionary = object as? [String: Any],
              let original = dictionary["lyric"] as? String,
              !original.isEmpty else { return nil }
        let translated = dictionary["tlyric"] as? String
        await MusicCache.shared.insert(CachedLyrics(original: original, translated: translated),
                                       for: cacheKey, ttl: 7 * 24 * 60 * 60)
        return (original, translated)
    }

    private func qqLyrics(songID: String) async throws -> (original: String, translated: String?)? {
        var components = URLComponents(string: "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg")!
        components.queryItems = [
            URLQueryItem(name: songID.allSatisfy(\.isNumber) ? "songid" : "songmid", value: songID),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "nobase64", value: "1")
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 8
        request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["code"] as? Int) == 0 else {
            throw MusicSourceError.invalidResponse("QQ 歌词接口响应异常")
        }
        func decode(_ value: Any?) -> String? {
            guard var text = value as? String, !text.isEmpty else { return nil }
            if !text.contains("["), let bytes = Data(base64Encoded: text),
               let decoded = String(data: bytes, encoding: .utf8), decoded.contains("[") {
                text = decoded
            }
            for (entity, literal) in [("&#10;", "\n"), ("&#13;", "\r"),
                                      ("&#39;", "'"), ("&apos;", "'"), ("&quot;", "\""),
                                      ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")] {
                text = text.replacingOccurrences(of: entity, with: literal)
            }
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
        }
        guard let original = decode(root["lyric"]) else { return nil }
        return (original, decode(root["trans"]))
    }

    private func request(_ query: [URLQueryItem]) async throws -> Any {
        guard var components = URLComponents(string: endpoint) else {
            throw MusicSourceError.invalidResponse("GDStudio 接口地址无效")
        }
        components.queryItems = query
        guard let url = components.url else {
            throw MusicSourceError.invalidResponse("无法生成元数据请求")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw MusicSourceError.invalidResponse("元数据 HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    private func extractURL(_ object: Any, key: String) -> URL? {
        guard let dictionary = object as? [String: Any],
              let raw = dictionary[key] as? String,
              let url = URL(string: raw),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    private func sourceName(_ source: MusicSource) -> String {
        switch source {
        case .netease: "netease"
        case .qq: "tencent"
        case .kuwo: "kuwo"
        case .kugou: "kugou"
        case .migu: "migu"
        case .qishui: "netease"
        case .youtubeMusic, .youtube, .spotify: "netease"
        }
    }
}
