import Foundation

/// Platform recommendation feeds are not necessarily official editorial collections.
/// Preserve their provenance and native playlist IDs; do not infer editorial ownership.
struct PlatformCollection: Identifiable, Sendable {
    enum Provider: String, Sendable { case qq, netease }
    let provider: Provider
    let sourceID: String
    let name: String
    let artworkURL: URL?
    var id: String { provider.rawValue + ":" + sourceID }
}

struct PlatformCollectionCatalog {
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    /// Returns everything exposed by the platform recommendation endpoint.
    /// These particular endpoints do not advertise a reliable pagination contract.
    /// An empty response is an error, not evidence that the catalog is exhaustive.
    func recommendedCollections() async throws -> [PlatformCollection] {
        async let qq = qqRecommendations()
        async let netease = neteaseRecommendations()
        let results = try await (qq, netease)
        var seen = Set<String>()
        return (results.0 + results.1).filter { seen.insert($0.id).inserted }
    }

    func qqRecommendations() async throws -> [PlatformCollection] {
        let url = URL(string: "https://u.y.qq.com/cgi-bin/musicu.fcg")!
        let body: [String: Any] = [
            "req_0": [
                "module": "playlist.HotRecommendServer",
                "method": "get_hot_recommend",
                "param": ["async": 1, "cmd": 2]
            ],
            "comm": ["uin": "0", "format": "json", "ct": 24, "cv": 0]
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let root = try await json(for: request)
        let envelope = root["req_0"] as? [String: Any] ?? [:]
        let data = envelope["data"] as? [String: Any] ?? [:]
        let rows = data["v_hot"] as? [[String: Any]] ?? []
        let collections = rows.compactMap { row -> PlatformCollection? in
            guard let rawID = row["content_id"] ?? row["dissid"],
                  let name = (row["title"] as? String) ?? (row["dissname"] as? String),
                  !name.isEmpty else { return nil }
            let artwork = (row["cover"] as? String) ?? (row["imgurl"] as? String)
            return PlatformCollection(
                provider: .qq, sourceID: String(describing: rawID),
                name: name,
                artworkURL: artwork.flatMap { URL(string: $0.replacingOccurrences(of: "http://", with: "https://")) }
            )
        }
        guard !collections.isEmpty else {
            throw MusicSourceError.invalidResponse("QQ 推荐合集接口没有返回有效内容")
        }
        return collections
    }

    func neteaseRecommendations() async throws -> [PlatformCollection] {
        var components = URLComponents(string: "https://music.163.com/api/personalized/playlist")!
        components.queryItems = [URLQueryItem(name: "limit", value: "1000")]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 12
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let root = try await json(for: request)
        let rows = root["result"] as? [[String: Any]] ?? root["data"] as? [[String: Any]] ?? []
        let collections = rows.compactMap { row -> PlatformCollection? in
            guard let rawID = row["id"],
                  let name = row["name"] as? String, !name.isEmpty else { return nil }
            let artwork = (row["picUrl"] as? String) ?? (row["coverImgUrl"] as? String)
            return PlatformCollection(
                provider: .netease, sourceID: String(describing: rawID),
                name: name, artworkURL: artwork.flatMap(URL.init(string:))
            )
        }
        guard !collections.isEmpty else {
            throw MusicSourceError.invalidResponse("网易云推荐合集接口没有返回有效内容")
        }
        return collections
    }

    /// First QQ collection feeds Daily Recommendations; first NetEase collection
    /// can feed Featured Songs. Keep platform ordering instead of hard-coded IDs.
    func firstCollectionSongs(provider: PlatformCollection.Provider, count: Int = 50) async throws -> [MusicSong] {
        let collections = try await (provider == .qq ? qqRecommendations() : neteaseRecommendations())
        guard let first = collections.first else {
            throw MusicSourceError.invalidResponse("平台没有返回推荐合集")
        }
        return try await tracks(for: first, count: count)
    }

    func tracks(for collection: PlatformCollection, count: Int = 50) async throws -> [MusicSong] {
        guard count > 0 else { return [] }
        switch collection.provider {
        case .netease:
            var components = URLComponents(string: "https://music.163.com/api/playlist/detail")!
            components.queryItems = [URLQueryItem(name: "id", value: collection.sourceID)]
            var request = URLRequest(url: components.url!)
            request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
            let root = try await json(for: request)
            let detail = root["result"] as? [String: Any] ?? root["playlist"] as? [String: Any] ?? [:]
            let rows = detail["tracks"] as? [[String: Any]] ?? []
            let songs = rows.prefix(count).compactMap { row -> MusicSong? in
                guard let id = row["id"] else { return nil }
                let artists = (row["ar"] as? [[String: Any]] ?? row["artists"] as? [[String: Any]] ?? [])
                    .compactMap { $0["name"] as? String }.joined(separator: " / ")
                let album = row["al"] as? [String: Any] ?? row["album"] as? [String: Any] ?? [:]
                return MusicSong(source: .netease, sourceID: String(describing: id),
                    title: row["name"] as? String ?? "未知歌曲",
                    artist: artists.isEmpty ? "未知歌手" : artists,
                    album: album["name"] as? String,
                    artworkURL: (album["picUrl"] as? String).flatMap(URL.init(string:)),
                    duration: (row["dt"] as? Double).map { $0 / 1000 },
                    hash: nil, albumID: album["id"].map { String(describing: $0) },
                    pictureID: nil, lyricID: String(describing: id))
            }
            guard !songs.isEmpty else { throw MusicSourceError.invalidResponse("网易云合集没有返回歌曲") }
            return songs
        case .qq:
            guard let playlistID = Int(collection.sourceID), playlistID > 0 else {
                throw MusicSourceError.invalidResponse("QQ 合集编号无效")
            }
            var songs: [MusicSong] = []
            var begin = 0
            while songs.count < count {
                try Task.checkCancellation()
                let body: [String: Any] = [
                    "req_0": [
                        "module": "music.srfDissInfo.aiDissInfo",
                        "method": "uniform_get_Dissinfo",
                        "param": ["disstid": playlistID, "song_begin": begin,
                                  "song_num": min(50, count - songs.count)]
                    ],
                    "comm": ["uin": "0", "format": "json", "ct": 24, "cv": 0]
                ]
                var request = URLRequest(url: URL(string: "https://u.y.qq.com/cgi-bin/musicu.fcg")!)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let root = try await json(for: request)
                let envelope = root["req_0"] as? [String: Any] ?? [:]
                let data = envelope["data"] as? [String: Any] ?? [:]
                let rows = data["songlist"] as? [[String: Any]] ?? []
                if rows.isEmpty { break }
                for row in rows {
                    guard let mid = row["mid"] as? String, !mid.isEmpty else { continue }
                    let artists = (row["singer"] as? [[String: Any]] ?? [])
                        .compactMap { $0["name"] as? String }.joined(separator: " / ")
                    let album = row["album"] as? [String: Any] ?? [:]
                    let albumMID = album["mid"] as? String
                    songs.append(MusicSong(source: .qq, sourceID: mid,
                        title: row["name"] as? String ?? "未知歌曲",
                        artist: artists.isEmpty ? "未知歌手" : artists,
                        album: album["name"] as? String,
                        artworkURL: albumMID.flatMap { URL(string: "https://y.gtimg.cn/music/photo_new/T002R300x300M000\($0).jpg") },
                        duration: (row["interval"] as? Double) ?? (row["interval"] as? Int).map(Double.init),
                        hash: nil, albumID: albumMID, pictureID: albumMID, lyricID: mid))
                }
                begin += rows.count
                if rows.count < 50 { break }
            }
            guard !songs.isEmpty else { throw MusicSourceError.invalidResponse("QQ 合集没有返回歌曲") }
            var seen = Set<String>()
            return songs.filter { seen.insert($0.id).inserted }.prefix(count).map { $0 }
        }
    }

    private func json(for request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw MusicSourceError.invalidResponse("合集接口 HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MusicSourceError.invalidResponse("合集接口不是 JSON 对象")
        }
        return object
    }
}
