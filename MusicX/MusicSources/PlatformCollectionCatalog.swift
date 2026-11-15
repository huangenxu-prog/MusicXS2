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
