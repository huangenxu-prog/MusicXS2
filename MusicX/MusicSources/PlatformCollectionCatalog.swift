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

    /// Keep platform catalogs independent, including same-name collections.
    func remainingRecommendedCollections() async throws -> [PlatformCollection] {
        async let qq = qqRecommendations()
        async let netease = neteaseRecommendations()
        let (qqRows, neteaseRows) = try await (qq, netease)
        return Array(qqRows.dropFirst()) + Array(neteaseRows.dropFirst())
    }

    /// A catalog request is not equivalent to loading every track. Load tracks
    /// on demand and deduplicate equivalent recordings by title and artist.
    func mergedTracks(for collections: [PlatformCollection], countPerCollection: Int = 50) async throws -> [MusicSong] {
        var merged: [MusicSong] = []
        var seen = Set<String>()
        for collection in collections {
            try Task.checkCancellation()
            let tracks = try await tracks(for: collection, count: countPerCollection)
            for song in tracks {
                let key = (song.title + "|" + song.artist)
                    .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                    .filter { $0.isLetter || $0.isNumber || $0 == "|" }
                if seen.insert(key).inserted { merged.append(song) }
            }
        }
        return merged
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

    /// Only the first collection is used; do not fill from later playlists.
    func firstCollectionSongs(provider: PlatformCollection.Provider, count: Int = 50) async throws -> [MusicSong] {
        guard count > 0 else { return [] }
        let collections = try await (provider == .qq ? qqRecommendations() : neteaseRecommendations())
        guard let first = collections.first else {
            throw MusicSourceError.invalidResponse("平台没有返回推荐合集")
        }
        return try await tracks(for: first, count: count)
    }

    /// Merge the first QQ and the first NetEase playlist, at most 50 unique songs.
    func firstTwoPlatformRecommendations(count: Int = 50) async throws -> [MusicSong] {
        guard count > 0 else { return [] }
        async let qqRows: [MusicSong] = (try? await firstCollectionSongs(provider: .qq, count: count)) ?? []
        async let neteaseRows: [MusicSong] = (try? await firstCollectionSongs(provider: .netease, count: count)) ?? []
        let (qq, netease) = await (qqRows, neteaseRows)
        var combined: [MusicSong] = []
        var seen = Set<String>()
        for index in 0..<max(qq.count, netease.count) {
            try Task.checkCancellation()
            for candidate in [index < qq.count ? qq[index] : nil,
                              index < netease.count ? netease[index] : nil].compactMap({ $0 }) {
                let key = (candidate.title + "|" + candidate.artist)
                    .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                    .filter { $0.isLetter || $0.isNumber || $0 == "|" }
                if seen.insert(key).inserted { combined.append(candidate) }
                if combined.count == count { return combined }
            }
        }
        guard !combined.isEmpty else {
            throw MusicSourceError.invalidResponse("QQ 和网易云首个推荐合集均未返回歌曲")
        }
        return combined
    }


    /// Import a user-shared QQ playlist. Never infer its contents from search
    /// results: the exact shared playlist ID is used for both metadata and songs.
    func importQQPlaylist(shareText: String) async throws -> (playlist: MusicPlaylist, songs: [MusicSong]) {
        let text = shareText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let link = text.split(whereSeparator: { $0.isWhitespace }).first(where: { $0.hasPrefix("https://") || $0.hasPrefix("http://") }),
              let components = URLComponents(string: String(link)),
              let host = components.host?.lowercased(),
              host == "qq.com" || host.hasSuffix(".qq.com") else {
            throw MusicSourceError.invalidResponse("请粘贴 QQ 音乐的歌单分享链接")
        }
        let queryID = components.queryItems?.first(where: { ["id", "disstid"].contains($0.name.lowercased()) })?.value
        let lastPath = components.path.split(separator: "/").last.map(String.init)
        let playlistID = queryID ?? (components.path.contains("/playlist/") ? lastPath : nil)
        guard let playlistID, !playlistID.isEmpty, playlistID.allSatisfy(\.isNumber),
              let numericID = Int(playlistID), numericID > 0 else {
            throw MusicSourceError.invalidResponse("无法从 QQ 音乐链接识别歌单编号")
        }

        let body: [String: Any] = [
            "req_0": [
                "module": "music.srfDissInfo.aiDissInfo",
                "method": "uniform_get_Dissinfo",
                "param": ["disstid": numericID, "song_begin": 0, "song_num": 50]
            ],
            "comm": ["uin": "0", "format": "json", "ct": 24, "cv": 0]
        ]
        var request = URLRequest(url: URL(string: "https://u.y.qq.com/cgi-bin/musicu.fcg")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let root = try await json(for: request)
        let envelope = root["req_0"] as? [String: Any] ?? [:]
        let data = envelope["data"] as? [String: Any] ?? [:]
        let dirinfo = data["dirinfo"] as? [String: Any] ?? [:]
        let metadata = data["dissinfo"] as? [String: Any] ?? [:]
        func firstNonEmpty(_ values: [Any?]) -> String? {
            values.compactMap { $0 as? String }.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        let title = firstNonEmpty([
            dirinfo["title"], dirinfo["dissname"], data["dissname"],
            metadata["title"], metadata["dissname"]
        ]) ?? "QQ 歌单 \(playlistID)"
        let cover = firstNonEmpty([
            dirinfo["picurl"], dirinfo["logo"], dirinfo["cover"],
            data["logo"], data["picurl"], metadata["logo"]
        ])
        let rawCount = dirinfo["songnum"] ?? dirinfo["song_num"] ?? data["total_song_num"] ?? data["songnum"]
        let declaredCount: Int? = (rawCount as? Int) ?? (rawCount as? NSNumber)?.intValue ?? (rawCount as? String).flatMap(Int.init)
        // An explicit upper bound avoids unbounded requests for malformed
        // server responses. A future background sync can page very large lists.
        let maxImportCount = 5000
        let requestedCount = min(max(declaredCount ?? 1000, 1), maxImportCount)
        let entry = PlatformCollection(provider: .qq, sourceID: playlistID, name: title,
                                       artworkURL: cover.flatMap { URL(string: $0.replacingOccurrences(of: "http://", with: "https://")) })
        let tracks = try await tracks(for: entry, count: requestedCount)
        try Task.checkCancellation()
        let playlist = MusicPlaylist(source: .qq, sourceID: playlistID,
                                     name: title, creator: nil, description: nil,
                                     artworkURL: entry.artworkURL, trackCount: tracks.count,
                                     provenance: .platformRecommended)
        return (playlist, tracks)
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
