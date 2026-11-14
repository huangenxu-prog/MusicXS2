import CommonCrypto
import CryptoKit
import Foundation

/// One deterministic playback chain:
/// NetEase -> matched QQ -> pyncmd(NetEase ID)
/// QQ -> matched NetEase -> pyncmd(matched NetEase ID)
///
/// Search, matching and URL resolution are separate responsibilities. This type
/// orchestrates them without changing the player or any UI state.
struct MusicSourceScheduler: MusicURLResolving {
    private let session: URLSession
    private let searchService: GDStudioMusicSearchService

    init(session: URLSession = .shared) {
        self.session = session
        self.searchService = GDStudioMusicSearchService()
    }

    func resolve(song: MusicSong, quality: MusicQuality = .high) async throws -> URL {
        let cacheKey = cacheKey(for: song, quality: quality)
        if let cached: URL = await MusicCache.shared.value(for: cacheKey) {
            do {
                try await verifyPlayableAudio(cached, duration: song.duration)
                return cached
            } catch {
                await MusicCache.shared.removeValue(for: cacheKey)
            }
        }

        var failures: [String] = []
        var matchedNeteaseSong: MusicSong?

        // 1. Always try the song's own platform first.
        do {
            let url = try await resolveNative(song, quality: quality)
            try await verifyPlayableAudio(url, duration: song.duration)
            await MusicCache.shared.insert(url, for: cacheKey, ttl: 180)
            MusicSourceDiagnostics.shared.record(
                event: "resolve", source: song.source.rawValue, provider: "native-primary",
                duration: 0, result: "success"
            )
            return url
        } catch {
            if isCancellation(error) { throw CancellationError() }
            failures.append("本平台原生解析：\(error.localizedDescription)")
            MusicSourceDiagnostics.shared.record(
                event: "resolve", source: song.source.rawValue, provider: "native-primary",
                duration: 0, result: "failed", detail: error.localizedDescription
            )
        }

        // 2. Search only the other primary platform. A different platform ID
        // must be obtained from a matched result; IDs are never reused across platforms.
        let alternateSource: MusicSource
        switch song.source {
        case .netease: alternateSource = .qq
        case .qq: alternateSource = .netease
        default:
            throw MusicSourceError.unsupportedSource(song.source)
        }

        do {
            let keyword = [song.title, song.artist].filter { !$0.isEmpty }.joined(separator: " ")
            let candidates = try await searchService.search(
                keyword: keyword, source: alternateSource, count: 20
            )
            if let match = MusicSongMatcher.bestMatch(for: song, among: candidates) {
                if match.source == .netease { matchedNeteaseSong = match }
                do {
                    let url = try await resolveNative(match, quality: quality)
                    try await verifyPlayableAudio(url, duration: song.duration)
                    await MusicCache.shared.insert(url, for: cacheKey, ttl: 180)
                    MusicSourceDiagnostics.shared.record(
                        event: "resolve", source: song.source.rawValue, provider: "cross-platform-\(alternateSource.rawValue)",
                        duration: 0, result: "success", detail: "matched_id=\(match.sourceID)"
                    )
                    return url
                } catch {
                    if isCancellation(error) { throw CancellationError() }
                    failures.append("跨平台原生解析：\(error.localizedDescription)")
                    MusicSourceDiagnostics.shared.record(
                        event: "resolve", source: song.source.rawValue, provider: "cross-platform-\(alternateSource.rawValue)",
                        duration: 0, result: "failed", detail: error.localizedDescription
                    )
                }
            } else {
                failures.append("跨平台未找到匹配歌曲")
                MusicSourceDiagnostics.shared.record(
                    event: "match", source: song.source.rawValue, provider: alternateSource.rawValue,
                    duration: 0, result: "no_match"
                )
            }
        } catch {
            if isCancellation(error) { throw CancellationError() }
            failures.append("跨平台搜索：\(error.localizedDescription)")
        }

        // 3. pyncmd is always the final fallback and always receives a NetEase ID.
        let neteaseSong: MusicSong?
        if song.source == .netease {
            neteaseSong = song
        } else {
            neteaseSong = matchedNeteaseSong
        }

        if let neteaseSong {
            do {
                let url = try await resolvePyncmd(neteaseSong, quality: quality)
                try await verifyPlayableAudio(url, duration: song.duration)
                await MusicCache.shared.insert(url, for: cacheKey, ttl: 180)
                MusicSourceDiagnostics.shared.record(
                    event: "resolve", source: song.source.rawValue, provider: "pyncmd",
                    duration: 0, result: "success", detail: "netease_id=\(neteaseSong.sourceID)"
                )
                return url
            } catch {
                if isCancellation(error) { throw CancellationError() }
                failures.append("pyncmd：\(error.localizedDescription)")
                MusicSourceDiagnostics.shared.record(
                    event: "resolve", source: song.source.rawValue, provider: "pyncmd",
                    duration: 0, result: "failed", detail: error.localizedDescription
                )
            }
        } else {
            failures.append("没有取得可用于 pyncmd 的网易云歌曲 ID")
        }

        throw MusicSourceError.noPlayableURL(
            source: song.source,
            details: failures.joined(separator: "；")
        )
    }

    func resolveFresh(song: MusicSong, quality: MusicQuality = .high) async throws -> URL {
        await MusicCache.shared.removeValue(for: cacheKey(for: song, quality: quality))
        return try await resolve(song: song, quality: quality)
    }

    private func cacheKey(for song: MusicSong, quality: MusicQuality) -> String {
        "source-scheduler|\(song.source.rawValue)|\(song.sourceID)|\(quality.rawValue)"
    }

    private func resolveNative(_ song: MusicSong, quality: MusicQuality) async throws -> URL {
        switch song.source {
        case .netease:
            return try await resolveNeteaseNative(song, quality: quality)
        case .qq:
            return try await resolveQQNative(song, quality: quality)
        default:
            throw MusicSourceError.unsupportedSource(song.source)
        }
    }

    // MARK: - NetEase official EAPI

    private func resolveNeteaseNative(_ song: MusicSong, quality: MusicQuality) async throws -> URL {
        guard Int(song.sourceID) != nil else {
            throw MusicSourceError.invalidResponse("网易云歌曲 ID 无效")
        }

        let path = "/api/song/enhance/player/url/v1"
        let payload = "{\"ids\":\"[\(song.sourceID)]\",\"level\":\"\(quality.neteaseLevel)\",\"encodeType\":\"flac\"}"
        let encrypted = try eapiParameters(path: path, payload: payload)
        guard let url = URL(string: "https://interface3.music.163.com\(path)") else {
            throw MusicSourceError.invalidResponse("网易云官方接口地址无效")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 Chrome/91.0.4472.164 Safari/537.36 NeteaseMusicDesktop/2.10.2.200154", forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        request.setValue("os=pc; appver=2.10.2.200154; osver=; deviceId=pyncm!", forHTTPHeaderField: "Cookie")
        request.httpBody = Data("params=\(encrypted)".utf8)

        let root = try await jsonResponse(for: request)
        guard let rows = root["data"] as? [[String: Any]], let row = rows.first else {
            throw MusicSourceError.invalidResponse("网易云官方接口没有返回歌曲数据")
        }
        if let trial = row["freeTrialInfo"], !(trial is NSNull) {
            throw MusicSourceError.invalidResponse("网易云仅返回 VIP 试听片段")
        }
        guard let value = row["url"] as? String, let streamURL = validHTTPURL(value) else {
            let code = root["code"].map { String(describing: $0) } ?? "unknown"
            throw MusicSourceError.invalidResponse("网易云官方没有可播放地址（code \(code)）")
        }
        return streamURL
    }

    private var unusedQualityMarker: String { "" }

    private func eapiParameters(path: String, payload: String) throws -> String {
        let signatureText = "nobody\(path)use\(payload)md5forencrypt"
        let digest = Insecure.MD5.hash(data: Data(signatureText.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let plain = Data("\(path)-36cd479b6b5-\(payload)-36cd479b6b5-\(digest)".utf8)
        let key = Data("e82ckenh8dichen8".utf8)
        var encrypted = Data(count: plain.count + kCCBlockSizeAES128)
        var moved = 0

        let status: CCCryptorStatus = key.withUnsafeBytes { keyBytes in
            plain.withUnsafeBytes { inputBytes in
                encrypted.withUnsafeMutableBytes { outputBytes in
                    CCCrypt(
                        CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionPKCS7Padding | kCCOptionECBMode),
                        keyBytes.baseAddress, key.count, nil,
                        inputBytes.baseAddress, plain.count,
                        outputBytes.baseAddress, encrypted.count, &moved
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            throw MusicSourceError.invalidResponse("网易云 EAPI 加密失败（\(status)）")
        }
        return encrypted.prefix(moved).map { String(format: "%02X", $0) }.joined()
    }

    // MARK: - QQ official CgiGetVkey

    private func resolveQQNative(_ song: MusicSong, quality: MusicQuality) async throws -> URL {
        let file: String
        switch quality {
        case .standard: file = "M500\(song.sourceID).mp3"
        case .high: file = "M800\(song.sourceID).mp3"
        case .lossless: file = "F000\(song.sourceID).flac"
        case .hires: file = "Q000\(song.sourceID).flac"
        }

        let guid = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(32))
        let requestBody: [String: Any] = [
            "req_0": [
                "module": "vkey.GetVkeyServer",
                "method": "CgiGetVkey",
                "param": [
                    "filename": [file],
                    "guid": guid,
                    "songmid": [song.sourceID],
                    "songtype": [0],
                    "uin": "0",
                    "loginflag": 0,
                    "platform": "20"
                ]
            ],
            "loginUin": "0",
            "comm": ["uin": "0", "format": "json", "ct": 24, "cv": 0]
        ]

        guard let endpoint = URL(string: "https://u.y.qq.com/cgi-bin/musicu.fcg") else {
            throw MusicSourceError.invalidResponse("QQ 官方接口地址无效")
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let root = try await jsonResponse(for: request)
        guard let req = root["req_0"] as? [String: Any],
              let data = req["data"] as? [String: Any],
              let info = (data["midurlinfo"] as? [[String: Any]])?.first,
              let purl = info["purl"] as? String, !purl.isEmpty else {
            throw MusicSourceError.invalidResponse("QQ 官方接口没有返回播放地址")
        }
        if info["freeTrialInfo"] != nil || purl.localizedCaseInsensitiveContains("RS0") {
            throw MusicSourceError.invalidResponse("QQ 仅返回试听片段")
        }
        let hosts = data["sip"] as? [String] ?? ["https://isure.stream.qqmusic.qq.com/"]
        for host in hosts {
            if let streamURL = validHTTPURL(host + purl) { return streamURL }
        }
        throw MusicSourceError.invalidResponse("QQ 返回的播放地址无效")
    }

    // MARK: - pyncmd (NetEase ID only)

    private func resolvePyncmd(_ neteaseSong: MusicSong, quality: MusicQuality) async throws -> URL {
        guard neteaseSong.source == .netease, Int(neteaseSong.sourceID) != nil else {
            throw MusicSourceError.invalidResponse("pyncmd 必须使用网易云歌曲 ID")
        }
        var components = URLComponents(string: "https://music-api.gdstudio.xyz/api.php")
        components?.queryItems = [
            URLQueryItem(name: "types", value: "url"),
            URLQueryItem(name: "source", value: "netease"),
            URLQueryItem(name: "id", value: neteaseSong.sourceID),
            URLQueryItem(name: "br", value: quality.gdstudioBitrate)
        ]
        guard let url = components?.url else {
            throw MusicSourceError.invalidResponse("pyncmd 请求地址无效")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let root = try await jsonResponse(for: request)
        guard let value = root["url"] as? String, let streamURL = validHTTPURL(value) else {
            throw MusicSourceError.invalidResponse("pyncmd 没有返回有效播放地址")
        }
        if let bitrate = root["br"] as? Int, bitrate <= 0 {
            throw MusicSourceError.invalidResponse("pyncmd 返回的音质无效")
        }
        return streamURL
    }

    // MARK: - Shared HTTP / validation

    private func jsonResponse(for request: URLRequest) async throws -> [String: Any] {
        try Task.checkCancellation()
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MusicSourceError.invalidResponse("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MusicSourceError.invalidResponse("接口响应不是 JSON 对象")
        }
        return object
    }

    private func validHTTPURL(_ value: String) -> URL? {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    private func verifyPlayableAudio(_ url: URL, duration: TimeInterval?) async throws {
        try Task.checkCancellation()
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 6
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let (_, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, [200, 206].contains(http.statusCode) else {
            throw MusicSourceError.invalidResponse("音频地址校验失败（HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)）")
        }
        let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        if !contentType.isEmpty,
           !contentType.contains("audio"),
           !contentType.contains("octet-stream"),
           !contentType.contains("application/ogg") {
            throw MusicSourceError.invalidResponse("返回内容不是音频（\(contentType)）")
        }
        let size = Int(http.value(forHTTPHeaderField: "Content-Length") ?? "") ?? 0
        if size > 0, let duration, duration > 0 {
            let minimum = max(128_000, Int(duration * 3_000))
            if size < minimum {
                throw MusicSourceError.invalidResponse("音频文件明显短于目标歌曲，疑似试听片段")
            }
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}

/// Cross-platform match rules modeled on Kumone's AudioSourceTrackMatcher.
/// Title, primary singer and version markers must agree. Duration may differ
/// by at most five seconds; if duration is unavailable, the album must agree.
enum MusicSongMatcher {
    static func bestMatch(for source: MusicSong, among candidates: [MusicSong]) -> MusicSong? {
        candidates
            .filter { matches(source, $0) }
            .sorted { score(source, $0) < score(source, $1) }
            .first
    }

    static func matches(_ source: MusicSong, _ candidate: MusicSong) -> Bool {
        let sourceTitle = normalized(source.title)
        let candidateTitle = normalized(candidate.title)
        guard !sourceTitle.isEmpty, sourceTitle == candidateTitle else { return false }

        let sourceArtist = primaryArtist(source.artist)
        let candidateArtist = primaryArtist(candidate.artist)
        guard !sourceArtist.isEmpty, sourceArtist != "未知歌手",
              sourceArtist == candidateArtist else { return false }

        guard versionMarkers(source.title) == versionMarkers(candidate.title) else { return false }

        if let lhs = source.duration, let rhs = candidate.duration, lhs > 0, rhs > 0 {
            return abs(lhs - rhs) <= 5
        }

        let lhsAlbum = normalized(source.album ?? "")
        let rhsAlbum = normalized(candidate.album ?? "")
        return !lhsAlbum.isEmpty && lhsAlbum == rhsAlbum
    }

    private static func score(_ source: MusicSong, _ candidate: MusicSong) -> Double {
        let durationScore: Double
        if let lhs = source.duration, let rhs = candidate.duration, lhs > 0, rhs > 0 {
            durationScore = abs(lhs - rhs)
        } else {
            durationScore = 5
        }
        let albumScore = normalized(source.album ?? "") == normalized(candidate.album ?? "") ? 0 : 1
        return durationScore + albumScore
    }

    private static func primaryArtist(_ value: String) -> String {
        let first = value.split(whereSeparator: { "/&、,，;；".contains($0) }).first.map(String.init) ?? value
        return normalized(first)
    }

    private static func versionMarkers(_ value: String) -> Set<String> {
        let markers = [
            "live", "现场", "演唱会", "remix", "伴奏", "instrumental", "纯音乐",
            "dj", "cover", "翻唱", "karaoke", "acoustic", "demo", "remaster"
        ]
        let text = normalized(value)
        return Set(markers.filter { text.contains(normalized($0)) })
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .unicodeScalars
            .filter(CharacterSet.alphanumerics.contains)
            .map(String.init)
            .joined()
    }
}

