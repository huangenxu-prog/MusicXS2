import SwiftUI

struct MXLightPlayer: View {
    let song: MXLightTrack?
    let queue: [MXLightTrack]
    let lyrics: [String]
    let activeLyricIndex: Int
    let isPlaying: Bool
    let isLoading: Bool
    let currentTime: Double
    let duration: Double
    let repeatMode: Int
    let shuffle: Bool
    let isFavorite: Bool
    @Binding var mode: String
    let onClose: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onSeek: (Double) -> Void
    let onRepeat: () -> Void
    let onShuffle: () -> Void
    let onFavorite: () -> Void
    let onQueuePlay: (Int) -> Void
    let onRemoveQueue: (Int) -> Void
    let onClearQueue: () -> Void

    @State private var scrubTime: Double = 0
    @State private var isScrubbing = false

    var body: some View {
        GeometryReader { geometry in
            let coverSide = min(geometry.size.width - 94, geometry.size.height * 0.39)
            VStack(spacing: 0) {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 21, weight: .medium))
                    }
                    Spacer()
                    Text("MusicX").font(.system(size: 17, weight: .semibold))
                    Spacer()
                    Menu {
                        Button("封面", systemImage: "square") { mode = "artwork" }
                        Button("歌词", systemImage: "text.aligncenter") { mode = "lyrics" }
                        Button("播放队列", systemImage: "list.bullet") { mode = "queue" }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 22)).frame(width: 30, height: 38)
                    }
                }
                .foregroundStyle(MXLight.ink)
                .padding(.horizontal, 26)
                .frame(height: 52)

                if mode == "artwork" {
                    Spacer(minLength: 10)
                    MXLightArtwork(url: song?.artworkURL, size: max(120, coverSide), variant: 0)
                        .shadow(color: MXLight.ink.opacity(0.16), radius: 16, y: 10)
                        .frame(maxWidth: .infinity)
                    Spacer(minLength: 10)
                } else if mode == "lyrics" {
                    lyricsView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    queueView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(song?.title ?? "尚未播放")
                            .font(.system(size: 23, weight: .bold))
                            .foregroundStyle(MXLight.ink)
                            .lineLimit(1)
                        Text(song?.artist ?? "选择一首歌曲开始播放")
                            .font(.system(size: 14))
                            .foregroundStyle(MXLight.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 10)
                    Button(action: onFavorite) {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .font(.system(size: 24))
                            .foregroundStyle(isFavorite ? MXLight.red : MXLight.ink)
                    }
                    .disabled(song == nil)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 16)

                VStack(spacing: 0) {
                    Slider(
                        value: Binding(
                            get: { isScrubbing ? scrubTime : min(max(currentTime, 0), max(duration, 1)) },
                            set: { scrubTime = $0 }
                        ),
                        in: 0...max(duration, 1),
                        onEditingChanged: { editing in
                            if editing {
                                scrubTime = currentTime
                                isScrubbing = true
                            } else {
                                isScrubbing = false
                                onSeek(scrubTime)
                            }
                        }
                    )
                    .tint(MXLight.red)
                    .disabled(duration <= 0)
                    HStack {
                        Text(time(isScrubbing ? scrubTime : currentTime))
                        Spacer()
                        Text(time(duration))
                    }
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(MXLight.muted)
                }
                .padding(.horizontal, 27)

                HStack(spacing: 0) {
                    Button(action: onShuffle) {
                        Image(systemName: "shuffle")
                            .foregroundStyle(shuffle ? MXLight.red : MXLight.muted)
                    }
                    Spacer()
                    Button(action: onPrevious) {
                        Image(systemName: "backward.end.fill")
                            .foregroundStyle(MXLight.ink)
                    }
                    Spacer()
                    Button(action: onPlayPause) {
                        Group {
                            if isLoading { ProgressView().tint(MXLight.ink) }
                            else {
                                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 26, weight: .bold))
                                    .foregroundStyle(MXLight.ink)
                            }
                        }
                        .frame(width: 66, height: 66)
                        .background(Color.white, in: Circle())
                        .shadow(color: MXLight.ink.opacity(0.1), radius: 12, y: 5)
                    }
                    .disabled(song == nil)
                    Spacer()
                    Button(action: onNext) {
                        Image(systemName: "forward.end.fill").foregroundStyle(MXLight.ink)
                    }
                    Spacer()
                    Button(action: onRepeat) {
                        Image(systemName: repeatMode == 2 ? "repeat.1" : "repeat")
                            .foregroundStyle(repeatMode == 0 ? MXLight.muted : MXLight.red)
                    }
                    .accessibilityLabel(repeatMode == 2 ? "单曲循环" : repeatMode == 1 ? "列表循环" : "不循环")
                }
                .font(.system(size: 20))
                .padding(.horizontal, 38)
                .frame(height: 92)

                HStack(spacing: 0) {
                    modeButton("封面", symbol: "square", value: "artwork")
                    modeButton("歌词", symbol: "text.aligncenter", value: "lyrics")
                    modeButton("播放队列", symbol: "list.bullet", value: "queue")
                }
                .frame(height: 74)
                .padding(.horizontal, 15)
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MXLight.background.ignoresSafeArea())
        }
        .preferredColorScheme(.light)
    }

    private func modeButton(_ text: String, symbol: String, value: String) -> some View {
        Button { mode = value } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 19))
                Text(text).font(.system(size: 11))
            }
            .foregroundStyle(mode == value ? MXLight.red : MXLight.muted)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var lyricsView: some View {
        ScrollViewReader { reader in
            ScrollView(showsIndicators: false) {
                if lyrics.isEmpty {
                    Text("暂时没有找到歌词")
                        .foregroundStyle(MXLight.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 100)
                } else {
                    VStack(spacing: 20) {
                        ForEach(Array(lyrics.enumerated()), id: \.offset) { index, text in
                            Text(text)
                                .font(.system(size: index == activeLyricIndex ? 22 : 16,
                                              weight: index == activeLyricIndex ? .bold : .medium))
                                .foregroundStyle(index == activeLyricIndex ? MXLight.red : MXLight.muted)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .id(index)
                        }
                    }
                    .padding(.horizontal, 30)
                    .padding(.vertical, 50)
                }
            }
            .onChange(of: activeLyricIndex) { _, index in
                guard lyrics.indices.contains(index) else { return }
                withAnimation(.easeInOut(duration: 0.22)) { reader.scrollTo(index, anchor: .center) }
            }
        }
    }

    private var queueView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("播放队列").font(.system(size: 19, weight: .bold))
                Text("\(queue.count) 首").font(.system(size: 12)).foregroundStyle(MXLight.muted)
                Spacer()
                Button("清空", action: onClearQueue).font(.system(size: 13))
            }
            .foregroundStyle(MXLight.ink)
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 5) {
                    ForEach(Array(queue.enumerated()), id: \.element.id) { i, track in
                        HStack(spacing: 8) {
                            Button { onQueuePlay(track.id) } label: {
                                HStack(spacing: 9) {
                                    MXLightArtwork(url: track.artworkURL, size: 43, variant: i)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(track.title).font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(song?.id == track.id ? MXLight.red : MXLight.ink)
                                            .lineLimit(1)
                                        Text(track.artist).font(.system(size: 11))
                                            .foregroundStyle(MXLight.muted).lineLimit(1)
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            Button { onRemoveQueue(track.id) } label: {
                                Image(systemName: "xmark").font(.system(size: 11))
                                    .foregroundStyle(MXLight.muted).frame(width: 24, height: 34)
                            }
                            .disabled(song?.id == track.id)
                        }
                    }
                }
            }
        }
        .padding(22)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func time(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "0:00" }
        let n = Int(value)
        return String(format: "%d:%02d", n / 60, n % 60)
    }
}

// Light-themed detail routes continue to use the original catalog, source IDs
// and playback queue; no duplicate resource engine is introduced.
struct MXLightDetail: View {
    let route: MusicDiscoveryRoute
    let favorites: [MusicSong]
    let onBack: () -> Void
    let onPlay: (MusicSong, [MusicSong]) -> Void
    let onOpen: (MusicDiscoveryRoute) -> Void
    let isFavorite: (MusicSong) -> Bool
    let onFavorite: (MusicSong) -> Void

    @State private var tracks: [MusicSong] = []
    @State private var playlists: [MusicPlaylist] = []
    @State private var loading = true
    @State private var message: String?
    @State private var chart = "热歌榜"

    private var title: String {
        switch route {
        case .daily: "每日推荐"
        case .featuredPick: "我喜欢"
        case .charts: "排行榜"
        case .chart(let name): name
        case .newReleases: "新歌速递"
        case .featuredPlaylists, .playlists: "推荐歌单"
        case .playlistByID(let item): item.name
        case .playlist(let name): name
        case .album(let title, _): title
        case .albums: "专辑"
        case .musicCategory(let name, _, _, _): name
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .medium))
                        .frame(width: 36, height: 38)
                }
                Spacer()
                Text(title).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                Spacer()
                Menu {
                    if let first = tracks.first {
                        Button("播放全部", systemImage: "play.fill") {
                            onPlay(first, tracks)
                        }
                        Button("随机播放", systemImage: "shuffle") {
                            if let random = tracks.randomElement() {
                                onPlay(random, tracks)
                            }
                        }
                    }
                    Button("返回", systemImage: "chevron.left", action: onBack)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 42, height: 38)
                }
            }
            .foregroundStyle(MXLight.ink)
            .padding(.horizontal, 18)
            .padding(.top, 8)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 19) {
                    HStack(spacing: 16) {
                        MXLightArtwork(url: playlists.first?.artworkURL ?? tracks.first?.artworkURL,
                                       size: 116)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(title).font(.system(size: 24, weight: .bold))
                                .foregroundStyle(MXLight.ink)
                                .lineLimit(2)
                            Text("\(tracks.count) 首歌曲")
                                .font(.system(size: 12)).foregroundStyle(MXLight.muted)
                            if let first = tracks.first {
                                Button { onPlay(first, tracks) } label: {
                                    Label("播放全部", systemImage: "play.fill")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 15).frame(height: 35)
                                        .background(MXLight.red, in: Capsule())
                                }
                            }
                        }
                    }

                    if case .charts = route {
                        HStack(spacing: 7) {
                            ForEach(["热歌榜", "飙升榜", "新歌榜"], id: \.self) { name in
                                Button(name) {
                                    chart = name
                                    Task { await loadChart(name) }
                                }
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(chart == name ? .white : MXLight.ink)
                                .frame(maxWidth: .infinity).frame(height: 36)
                                .background(chart == name ? MXLight.teal : MXLight.paper, in: Capsule())
                            }
                        }
                    }
                    if loading { ProgressView("正在加载").tint(MXLight.teal).frame(maxWidth: .infinity) }
                    if let message { Text(message).foregroundStyle(MXLight.muted).font(.system(size: 13)) }
                    if !playlists.isEmpty && (isPlaylistGrid || route.id == "albums") {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                            ForEach(Array(playlists.enumerated()), id: \.element.id) { i, item in
                                Button { onOpen(.playlistByID(item)) } label: {
                                    VStack(alignment: .leading, spacing: 7) {
                                        GeometryReader { proxy in
                                            MXLightArtwork(url: item.artworkURL, size: proxy.size.width, variant: i)
                                        }.aspectRatio(1, contentMode: .fit)
                                        Text(item.name).font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(MXLight.ink).lineLimit(2)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else {
                        LazyVStack(spacing: 5) {
                            ForEach(Array(tracks.enumerated()), id: \.element.id) { i, track in
                                MXLightTrackRow(
                                    track: MXLightTrack(id: stableID(track), title: track.title,
                                                        artist: track.artist, album: track.album ?? "",
                                                        artworkURL: track.artworkURL), index: i,
                                    onPlay: { onPlay(track, tracks) },
                                    onFavorite: { onFavorite(track) },
                                    favorite: isFavorite(track))
                                if i < tracks.count - 1 { MXLight.line.frame(height: 0.5) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 22)
                .padding(.bottom, 90)
            }
        }
        .background(MXLight.background.ignoresSafeArea())
        .task(id: route.id) { await load() }
        .simultaneousGesture(
            DragGesture(minimumDistance: 22, coordinateSpace: .global)
                .onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard value.startLocation.x <= 36,
                          dx >= 80, dx > abs(dy) * 1.35 else { return }
                    onBack()
                }
        )
        .preferredColorScheme(.light)
    }

    private var isPlaylistGrid: Bool {
        switch route {
        case .featuredPlaylists, .playlists: true
        default: false
        }
    }

    @MainActor private func loadChart(_ name: String) async {
        loading = true
        defer { loading = false }
        tracks = (try? await MusicCatalogSearchEngine().toplist(name, count: 50)) ?? []
    }

    @MainActor private func load() async {
        loading = true
        message = nil
        tracks = []
        playlists = []
        defer { loading = false }
        let catalog = MusicCatalogSearchEngine()
        do {
            switch route {
            case .daily:
                tracks = try await PlatformCollectionCatalog().firstTwoPlatformRecommendations(count: 50)
            case .featuredPick:
                tracks = favorites
            case .charts:
                tracks = try await catalog.toplist(chart, count: 50)
            case .chart(let name):
                chart = name
                tracks = try await catalog.toplist(name, count: 50)
            case .newReleases:
                tracks = try await catalog.toplist("新歌榜", count: 50)
            case .featuredPlaylists, .playlists:
                playlists = try await catalog.featuredPlaylists(count: 30)
            case .playlistByID(let playlist):
                tracks = try await catalog.playlistTracks(playlistID: playlist.sourceID, source: playlist.source, count: 100)
            case .playlist(let name):
                tracks = try await catalog.playlistTracks(keyword: name, count: 50)
            case .album(let name, let artist):
                let rows = (try? await catalog.search(keyword: name, source: .netease,
                                                     count: 50, albumOnly: true)) ?? []
                tracks = rows.filter { ($0.album ?? "").localizedCaseInsensitiveContains(name)
                    && $0.artist.localizedCaseInsensitiveContains(artist) }
            case .albums:
                message = "请从首页的精选专辑进入具体专辑"
            case .musicCategory(_, _, _, let keyword):
                tracks = try await catalog.search(keyword: keyword, source: .netease, count: 50)
            }
            if tracks.isEmpty && playlists.isEmpty && message == nil {
                message = "暂无可展示内容，请稍后重试"
            }
        } catch {
            message = "加载失败：\(error.localizedDescription)"
        }
    }

    private func stableID(_ track: MusicSong) -> Int {
        let hash = track.id.utf8.reduce(UInt64(14695981039346656037)) {
            ($0 ^ UInt64($1)) &* 1099511628211
        }
        return Int(hash & 0x7FFFFFFFFFFFFFFF)
    }
}
