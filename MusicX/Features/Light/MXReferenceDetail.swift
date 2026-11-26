import SwiftUI

/// Reference screens 07/08/09/10/11: visual presentation with live provider data.
struct MXReferenceDetail: View {
    let route: MusicDiscoveryRoute
    let favorites: [MusicSong]
    let onBack: () -> Void
    let onPlay: (MusicSong, [MusicSong]) -> Void
    let onOpen: (MusicDiscoveryRoute) -> Void
    let isFavorite: (MusicSong) -> Bool
    let onFavorite: (MusicSong) -> Void
    let currentTrackID: Int?
    let isPlaying: Bool

    @State private var tracks: [MusicSong] = []
    @State private var playlists: [MusicPlaylist] = []
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var chart = "热歌榜"

    private var isArtist: Bool {
        if case .musicCategory(_, let subtitle, _, _) = route {
            return subtitle == "歌手"
        }
        return false
    }

    private var isAlbum: Bool {
        if case .album = route { return true }
        return false
    }

    private var isCharts: Bool {
        switch route {
        case .charts, .chart: return true
        default: return false
        }
    }

    private var isPlaylistGrid: Bool {
        switch route {
        case .featuredPlaylists, .playlists: return true
        default: return false
        }
    }

    private var isDaily: Bool {
        if case .daily = route { return true }
        return false
    }

    private var visibleTitle: String {
        switch route {
        case .daily: "每日推荐"
        case .newReleases: "新歌速递"
        case .featuredPick: "我喜欢"
        case .charts, .chart: "排行榜"
        case .featuredPlaylists, .playlists: "推荐歌单"
        case .playlistByID(let playlist): playlist.name
        case .playlist(let name): name
        case .album(let name, _): name
        case .albums: "专辑"
        case .musicCategory(let title, _, _, _): title
        }
    }

    private var contentTitle: String {
        switch route {
        case .playlistByID(let playlist): playlist.name
        case .playlist(let name): name
        case .album(let name, _): name
        case .musicCategory(let title, _, _, _): title
        case .featuredPick: "我喜欢"
        case .newReleases: "新歌速递"
        default: visibleTitle
        }
    }

    private var headerCover: URL? {
        switch route {
        case .playlistByID(let playlist): playlist.artworkURL ?? tracks.first?.artworkURL
        default: tracks.first?.artworkURL ?? playlists.first?.artworkURL
        }
    }

    private var albumArtist: String? {
        if case .album(_, let artist) = route { return artist }
        return nil
    }

    private var playlistInfo: MusicPlaylist? {
        if case .playlistByID(let item) = route { return item }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if isDaily {
                        dailyIntro
                    } else if isCharts {
                        chartIntro
                    } else if isArtist {
                        artistIntro
                    } else if isAlbum {
                        albumIntro
                    } else if isPlaylistGrid {
                        MXLightSectionTitle(title: "精选推荐歌单")
                            .padding(.bottom, 18)
                    } else {
                        playlistIntro
                    }

                    if isLoading {
                        ProgressView("正在加载音乐")
                            .tint(MXLight.teal)
                            .frame(maxWidth: .infinity, minHeight: 85)
                    }
                    if let errorText {
                        Text(errorText)
                            .font(.system(size: 13))
                            .foregroundStyle(MXLight.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 12)
                    }

                    if isPlaylistGrid {
                        playlistGrid
                    } else if !tracks.isEmpty {
                        songListSection
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
        }
        .background(MXLight.background.ignoresSafeArea())
        .preferredColorScheme(.light)
        .task(id: route.id) { await load() }
        .simultaneousGesture(
            DragGesture(minimumDistance: 24, coordinateSpace: .global)
                .onEnded { gesture in
                    let dx = gesture.translation.width, dy = gesture.translation.height
                    guard gesture.startLocation.x <= 36,
                          dx > 85, dx > abs(dy) * 1.35 else { return }
                    onBack()
                }
        )
    }

    private var topBar: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 19))
                    .frame(width: 40, height: 42, alignment: .leading)
            }
            Spacer(minLength: 0)
            Text(visibleTitle.count > 16 ? "" : visibleTitle)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(MXLight.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
            Menu {
                if let first = tracks.first {
                    Button("播放全部", systemImage: "play.fill") {
                        onPlay(first, tracks)
                    }
                    Button("随机播放", systemImage: "shuffle") {
                        if let random = tracks.randomElement() { onPlay(random, tracks) }
                    }
                }
                Button("返回", systemImage: "chevron.left", action: onBack)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 21, weight: .semibold))
                    .frame(width: 40, height: 42, alignment: .trailing)
            }
        }
        .foregroundStyle(MXLight.ink)
        .padding(.horizontal, 24)
        .padding(.top, 5)
    }

    private var playlistIntro: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .top, spacing: 18) {
                MXLightArtwork(url: headerCover, size: 135, variant: 0)
                    .shadow(color: MXLight.shadow, radius: 12, y: 5)
                VStack(alignment: .leading, spacing: 8) {
                    if let playlistInfo {
                        Text(playlistInfo.source.displayName + " · 推荐歌单")
                            .font(.system(size: 12)).foregroundStyle(MXLight.muted)
                    }
                    Text(contentTitle)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(MXLight.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(tracks.count) 首歌曲")
                        .font(.system(size: 13)).foregroundStyle(MXLight.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let info = playlistInfo, let description = info.description,
               !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(description)
                    .font(.system(size: 13)).foregroundStyle(MXLight.muted)
                    .lineLimit(3)
            }
            playActions
        }
    }

    private var albumIntro: some View {
        VStack(spacing: 12) {
            MXLightArtwork(url: headerCover, size: 224, variant: 3)
                .shadow(color: MXLight.shadow, radius: 14, y: 7)
                .padding(.top, 4)
            Text(contentTitle)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(MXLight.ink)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
            if let albumArtist {
                Text(albumArtist)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(MXLight.teal)
            }
            Text("专辑 · \(tracks.count) 首")
                .font(.system(size: 13))
                .foregroundStyle(MXLight.muted)
            HStack(spacing: 12) {
                Button {
                    if let first = tracks.first { onPlay(first, tracks) }
                } label: {
                    Label("播放全部", systemImage: "play.fill")
                }
                .buttonStyle(MXReferencePill(isPrimary: true))
                .disabled(tracks.isEmpty)
                Button {
                    for track in tracks where !isFavorite(track) {
                        onFavorite(track)
                    }
                } label: {
                    Label("收藏歌曲", systemImage: "heart")
                }
                .buttonStyle(MXReferencePill(isPrimary: false))
                .disabled(tracks.isEmpty)
            }
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
    }

    private var artistIntro: some View {
        VStack(spacing: 12) {
            MXLightArtwork(url: headerCover, size: 148, variant: 0)
                .clipShape(Circle())
                .shadow(color: MXLight.shadow, radius: 12, y: 6)
                .padding(.top, 6)
            Text(contentTitle)
                .font(.system(size: 27, weight: .bold))
                .foregroundStyle(MXLight.ink)
            Text("歌手 · \(tracks.count) 首相关歌曲")
                .font(.system(size: 13))
                .foregroundStyle(MXLight.muted)
            Button {
                if let first = tracks.first { onPlay(first, tracks) }
            } label: {
                Label("播放热门", systemImage: "play.fill")
                    .padding(.horizontal, 17)
            }
            .buttonStyle(MXReferencePill(isPrimary: true))
            .fixedSize(horizontal: true, vertical: false)
            .disabled(tracks.isEmpty)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 12)
    }

    private var dailyIntro: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 22)
                    .fill(MXLight.ochre)
                Circle()
                    .fill(MXLight.teal)
                    .frame(width: 106, height: 106)
                    .offset(x: 285, y: -72)
                VStack(alignment: .leading, spacing: 7) {
                    Text(Date().formatted(.dateTime.month(.twoDigits).day(.twoDigits)))
                        .font(.system(size: 12))
                        .foregroundStyle(MXLight.ink.opacity(0.7))
                    Text("今天，听点好的。")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(MXLight.ink)
                    Text("推荐合集 · \(tracks.count) 首")
                        .font(.system(size: 12))
                        .foregroundStyle(MXLight.ink)
                }
                .padding(20)
            }
            .frame(height: 160)
            .clipped()
            Text("音乐来自在线平台推荐合集；不是基于个人历史训练的算法推荐。")
                .font(.system(size: 12))
                .foregroundStyle(MXLight.muted)
            playActions
        }
    }

    private var chartIntro: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                chartTile("热歌榜", sub: "Top 50", icon: "music.note",
                          color: MXLight.pink)
                chartTile("飙升榜", sub: "热度上升", icon: "arrow.up.right",
                          color: MXLight.cream)
                chartTile("新歌榜", sub: "最新 50 首", icon: "opticaldisc",
                          color: MXLight.ochre)
            }
            HStack(spacing: 12) {
                Button {
                    if let first = tracks.first { onPlay(first, tracks) }
                } label: { Label("播放榜单", systemImage: "play.fill") }
                    .buttonStyle(MXReferencePill(isPrimary: true))
                    .disabled(tracks.isEmpty)
                Text("在线更新")
                    .font(.system(size: 12))
                    .foregroundStyle(MXLight.muted)
            }
        }
    }

    private func chartTile(_ title: String, sub: String, icon: String, color: Color) -> some View {
        Button {
            chart = title
            Task { await loadChart(title) }
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(sub).font(.system(size: 10))
                    .foregroundStyle(MXLight.muted)
            }
            .foregroundStyle(MXLight.ink)
            .padding(11)
            .frame(maxWidth: .infinity)
            .frame(height: 110)
            .background(color, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(chart == title ? MXLight.red : .clear, lineWidth: 1.5))
        }.buttonStyle(.plain)
    }

    private var playActions: some View {
        HStack(spacing: 12) {
            Button {
                if let first = tracks.first { onPlay(first, tracks) }
            } label: { Label("播放全部", systemImage: "play.fill") }
                .buttonStyle(MXReferencePill(isPrimary: true))
                .disabled(tracks.isEmpty)
            Button {
                if let random = tracks.randomElement() { onPlay(random, tracks) }
            } label: { Label("随机播放", systemImage: "shuffle") }
                .buttonStyle(MXReferencePill(isPrimary: false))
                .disabled(tracks.isEmpty)
        }
        .padding(.top, 6)
    }

    private var songListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(isArtist ? "热门歌曲" : isAlbum ? "曲目" :
                     isDaily ? "今日歌曲" : isCharts ? chart + " TOP 50" : "歌曲列表")
                    .font(.system(size: 15, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(MXLight.headingMuted)
                Spacer()
                Text("共 \(tracks.count) 首")
                    .font(.system(size: 12)).foregroundStyle(MXLight.muted)
            }
            .padding(.bottom, 4)
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, song in
                HStack(spacing: 8) {
                    Text("\(index + 1)")
                        .font(.system(size: 13, weight: index < 3 ? .bold : .regular))
                        .foregroundStyle(index < 3 ? MXLight.red : MXLight.muted)
                        .frame(width: 18)
                    MXLightTrackRow(
                        track: MXLightTrack(
                            id: stableID(song), title: song.title, artist: song.artist,
                            album: song.album ?? "", artworkURL: song.artworkURL,
                            duration: song.duration, source: song.source
                        ),
                        index: index,
                        onPlay: { onPlay(song, tracks) },
                        onFavorite: { onFavorite(song) },
                        favorite: isFavorite(song),
                        isCurrent: stableID(song) == currentTrackID,
                        isPlaying: isPlaying
                    )
                }
            }
        }
        .padding(.top, 27)
    }

    private var playlistGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14),
                            GridItem(.flexible(), spacing: 14)], spacing: 18) {
            ForEach(Array(playlists.enumerated()), id: \.element.id) { index, playlist in
                Button { onOpen(.playlistByID(playlist)) } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        GeometryReader { proxy in
                            MXLightArtwork(url: playlist.artworkURL,
                                           size: proxy.size.width, variant: index)
                        }
                        .aspectRatio(1, contentMode: .fit)
                        Text(playlist.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(MXLight.ink)
                            .lineLimit(2)
                        Text("\(playlist.source.displayName) · \(playlist.trackCount ?? 0) 首")
                            .font(.system(size: 12))
                            .foregroundStyle(MXLight.muted)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
            }
        }
    }

    private func stableID(_ song: MusicSong) -> Int {
        let hash = song.id.utf8.reduce(UInt64(14695981039346656037)) {
            ($0 ^ UInt64($1)) &* 1099511628211
        }
        return Int(hash & 0x7FFFFFFFFFFFFFFF)
    }

    @MainActor private func loadChart(_ name: String) async {
        isLoading = true
        defer { isLoading = false }
        let updated = (try? await MusicCatalogSearchEngine().toplist(name, count: 50)) ?? []
        if !updated.isEmpty { tracks = updated }
    }

    @MainActor private func load(forceRefresh: Bool = false) async {
        isLoading = true
        errorText = nil
        if !forceRefresh { tracks = []; playlists = [] }
        defer { isLoading = false }
        let catalog = MusicCatalogSearchEngine()
        do {
            switch route {
            case .daily:
                tracks = try await PlatformCollectionCatalog()
                    .firstTwoPlatformRecommendations(count: 50)
            case .featuredPick:
                tracks = favorites
            case .charts:
                tracks = try await catalog.toplist(chart, count: 50, forceRefresh: forceRefresh)
            case .chart(let name):
                chart = name
                tracks = try await catalog.toplist(name, count: 50, forceRefresh: forceRefresh)
            case .newReleases:
                tracks = try await catalog.toplist("新歌榜", count: 50, forceRefresh: forceRefresh)
                MusicSourceDiagnostics.shared.record(event: "chart-display", source: "light", provider: "新歌榜", duration: 0, result: "loaded", detail: "qq=\(tracks.filter { $0.source == .qq }.count) netease=\(tracks.filter { $0.source == .netease }.count)")
                for (index, song) in tracks.prefix(10).enumerated() {
                    MusicSourceDiagnostics.shared.record(event: "chart-display-track", source: song.source.rawValue, provider: "新歌榜", duration: 0, result: "loaded", detail: "rank=\(index + 1) title=\(song.title) artist=\(song.artist)")
                }
            case .featuredPlaylists, .playlists:
                playlists = try await catalog.featuredPlaylists(count: 30, forceRefresh: forceRefresh)
            case .playlistByID(let playlist):
                tracks = try await catalog.playlistTracks(
                    playlistID: playlist.sourceID, source: playlist.source, count: 100, forceRefresh: forceRefresh)
            case .playlist(let name):
                tracks = try await catalog.playlistTracks(keyword: name, count: 50, forceRefresh: forceRefresh)
            case .album(let title, let artist):
                let netease = (try? await catalog.search(
                    keyword: title, source: .netease, count: 50, albumOnly: true)) ?? []
                let qq = (try? await catalog.search(
                    keyword: title, source: .qq, count: 50, albumOnly: true)) ?? []
                var ids = Set<String>()
                tracks = (netease + qq).filter {
                    ($0.album ?? "").localizedCaseInsensitiveContains(title)
                    && $0.artist.localizedCaseInsensitiveContains(artist)
                    && ids.insert($0.id).inserted
                }
            case .albums:
                errorText = "请从首页的精选专辑进入具体专辑"
            case .musicCategory(_, let subtitle, _, let keyword):
                if subtitle == "歌手" {
                    let netease = (try? await catalog.search(
                        keyword: keyword, source: .netease, count: 50)) ?? []
                    let qq = (try? await catalog.search(
                        keyword: keyword, source: .qq, count: 50)) ?? []
                    var ids = Set<String>()
                    tracks = (netease + qq).filter {
                        $0.artist.localizedCaseInsensitiveContains(keyword)
                        && ids.insert($0.id).inserted
                    }
                } else {
                    tracks = try await catalog.search(
                        keyword: keyword, source: .netease, count: 50)
                }
            }
            if tracks.isEmpty && playlists.isEmpty && errorText == nil {
                errorText = "暂无可展示内容，请稍后重试"
            }
        } catch {
            if tracks.isEmpty && playlists.isEmpty { errorText = "加载失败：\(error.localizedDescription)" }
        }
    }
}
