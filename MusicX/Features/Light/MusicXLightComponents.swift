import SwiftUI

// MusicX warm-light skin. The classic dark views and all playback/data services
// remain separate; these components are presentation only.
enum MXLight {
    static let background = Color(red: 247/255, green: 245/255, blue: 241/255)
    static let ink = Color(red: 27/255, green: 26/255, blue: 23/255)
    static let muted = Color(red: 117/255, green: 111/255, blue: 101/255)
    static let teal = Color(red: 47/255, green: 93/255, blue: 98/255)
    static let red = Color(red: 217/255, green: 72/255, blue: 43/255)
    static let ochre = Color(red: 233/255, green: 180/255, blue: 76/255)
    static let line = Color(red: 230/255, green: 224/255, blue: 213/255)
    static let paper = Color(red: 255/255, green: 254/255, blue: 252/255)
    static let cream = Color(red: 236/255, green: 228/255, blue: 214/255)
    static let coal = Color(red: 59/255, green: 58/255, blue: 54/255)
    static let pink = Color(red: 242/255, green: 184/255, blue: 166/255)
    static let lightTeal = Color(red: 224/255, green: 233/255, blue: 231/255)
    static let headingMuted = Color(red: 107/255, green: 101/255, blue: 92/255)
    static let shadow = ink.opacity(0.075)
}

struct MXLightTrack: Identifiable {
    let id: Int
    let title: String
    let artist: String
    let album: String
    let artworkURL: URL?
    var duration: TimeInterval? = nil
}

struct MXLightCollection: Identifiable {
    let id: String
    let name: String
    let count: Int?
    let artworkURL: URL?
}

// The twelve fallback covers recreate the shapes in index.html (art c1...c12).
// Actual QQ/NetEase cover images always take precedence over geometric art.
struct MXLightArtwork: View {
    let url: URL?
    var size: CGFloat = 54
    var variant: Int = 0

    private var pattern: Int { ((variant % 12) + 12) % 12 + 1 }
    private var base: Color {
        switch pattern {
        case 1, 6, 12: MXLight.teal
        case 2, 8: MXLight.red
        case 3, 10: MXLight.coal
        case 4, 7: MXLight.ochre
        case 5, 11: MXLight.pink
        default: MXLight.cream
        }
    }

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        geometric
                    }
                }
            } else {
                geometric
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: max(7, size * 0.105),
                                    style: .continuous))
    }

    private var geometric: some View {
        GeometryReader { proxy in
            let n = proxy.size.width
            ZStack {
                base
                switch pattern {
                case 1:
                    Circle().fill(MXLight.ochre).frame(width: n * 0.63, height: n * 0.63)
                case 2:
                    Rectangle().fill(MXLight.background).frame(height: n / 3)
                case 3:
                    Circle().stroke(MXLight.ochre, lineWidth: max(3, n * 0.09))
                        .frame(width: n * 0.55, height: n * 0.55)
                case 4:
                    Circle().fill(MXLight.teal).frame(width: n * 0.54)
                        .offset(x: n * 0.41, y: n * 0.41)
                case 5:
                    Circle().fill(MXLight.red).frame(width: n * 0.42)
                case 6:
                    Circle().fill(MXLight.red).frame(width: n * 0.85)
                        .offset(x: n * 0.51, y: -n * 0.46)
                    Circle().fill(MXLight.ochre).frame(width: n * 0.60)
                        .offset(x: -n * 0.51, y: n * 0.49)
                case 7:
                    Rectangle().fill(MXLight.pink).frame(height: n * 0.34)
                case 8:
                    Circle().stroke(MXLight.ochre, lineWidth: max(3, n * 0.09))
                        .frame(width: n * 0.50)
                case 9:
                    Circle().fill(MXLight.teal).frame(width: n * 0.90)
                        .offset(y: n * 0.48)
                case 10:
                    Rectangle().fill(MXLight.pink).frame(width: n * 0.36, height: n * 1.5)
                        .rotationEffect(.degrees(45))
                case 11:
                    Circle().fill(MXLight.ochre).frame(width: n * 0.70)
                        .offset(x: -n * 0.45, y: -n * 0.45)
                default:
                    Rectangle().fill(MXLight.cream).frame(width: n * 1.2, height: n * 0.32)
                        .rotationEffect(.degrees(-24)).offset(y: n * 0.20)
                }
            }
            .frame(width: n, height: n)
            .clipped()
        }
    }
}

struct MXLightSectionTitle: View {
    let title: String
    var onMore: (() -> Void)? = nil
    var moreLabel = "查看全部"

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .tracking(1.9)
                .foregroundStyle(MXLight.headingMuted)
            Spacer()
            if let onMore {
                Button(action: onMore) {
                    HStack(spacing: 3) {
                        Text(moreLabel)
                        Image(systemName: "chevron.right").font(.system(size: 10))
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(MXLight.muted)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct MXLightTrackRow: View {
    let track: MXLightTrack
    let index: Int
    let onPlay: () -> Void
    var onFavorite: (() -> Void)? = nil
    var favorite = false

    private var durationText: String? {
        guard let seconds = track.duration, seconds.isFinite, seconds > 0 else { return nil }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPlay) {
                HStack(spacing: 12) {
                    MXLightArtwork(url: track.artworkURL, size: 48, variant: index)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(MXLight.ink)
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.system(size: 12))
                            .foregroundStyle(MXLight.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let durationText {
                Text(durationText)
                    .font(.system(size: 12))
                    .foregroundStyle(MXLight.muted)
                    .monospacedDigit()
            }
            Menu {
                Button("播放", systemImage: "play.fill", action: onPlay)
                if let onFavorite {
                    Button(favorite ? "取消收藏" : "收藏歌曲",
                           systemImage: favorite ? "heart.slash" : "heart",
                           action: onFavorite)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(MXLight.muted)
                    .frame(width: 28, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("更多操作：\(track.title)")
        }
        .padding(.vertical, 6)
    }
}

struct MXLightHome: View {
    let songs: [MXLightTrack]
    let collections: [MXLightCollection]
    let onDaily: () -> Void
    let onFavorites: () -> Void
    let onCharts: () -> Void
    let onNew: () -> Void
    let onAllCollections: () -> Void
    let onScene: (String) -> Void
    let onSong: (Int) -> Void
    let isFavorite: (Int) -> Bool
    let onFavorite: (Int) -> Void
    let onCollection: (String) -> Void
    let onAlbum: (String, String) -> Void
    let onArtist: (String) -> Void
    let onSettings: () -> Void

    private var albums: [MXLightTrack] {
        var seen = Set<String>()
        return songs.filter {
            !$0.album.isEmpty && seen.insert($0.album + "|" + $0.artist).inserted
        }
    }
    private var artists: [MXLightTrack] {
        var seen = Set<String>()
        return songs.filter { !$0.artist.isEmpty && seen.insert($0.artist).inserted }
    }
    private var dateText: String {
        let date = Date()
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "EEEE · M月d日"
        return f.string(from: date)
    }
    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 0..<6: return "夜深了"
        case 6..<12: return "早上好"
        case 12..<18: return "下午好"
        default: return "晚上好"
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(dateText)
                            .font(.system(size: 12))
                            .foregroundStyle(MXLight.muted)
                        Text(greeting)
                            .font(.system(size: 30, weight: .heavy))
                            .foregroundStyle(MXLight.ink)
                            .tracking(-0.5)
                    }
                    Spacer()
                    Button(action: onSettings) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 23, weight: .regular))
                            .foregroundStyle(MXLight.ink)
                            .frame(width: 40, height: 40)
                            .background(MXLight.cream, in: Circle())
                    }
                    .accessibilityLabel("设置")
                }
                .padding(.bottom, 22)

                Button {
                    // This is a random song from the already loaded recommendation
                    // catalog, not an unimplemented personalized radio algorithm.
                    if let id = songs.randomElement()?.id { onSong(id) }
                } label: {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("不知道听什么？")
                                .font(.system(size: 13))
                                .foregroundStyle(Color(red: 216/255, green: 210/255, blue: 198/255))
                            Text("一键随心听")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        Spacer()
                        Image(systemName: "play.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 64)
                            .background(MXLight.red, in: Circle())
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 139)
                    .background(MXLight.ink, in: RoundedRectangle(cornerRadius: 24))
                }
                .buttonStyle(.plain)
                .disabled(songs.isEmpty)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        ForEach(["驾车", "通勤", "专注", "放松", "睡前"], id: \.self) { title in
                            Button(title) { onScene(title) }
                                .font(.system(size: 14))
                                .foregroundStyle(MXLight.ink)
                                .padding(.horizontal, 17)
                                .frame(height: 40)
                                .background(MXLight.cream, in: Capsule())
                        }
                    }
                }
                .padding(.top, 18)

                HStack(spacing: 12) {
                    promo("每日推荐", description: "30 首 · 每日更新",
                          color: MXLight.ochre, text: MXLight.ink, action: onDaily)
                    promo("排行榜", description: "热歌 · 飙升 · 新歌",
                          color: MXLight.teal, text: .white, action: onCharts)
                }
                .padding(.top, 18)

                VStack(alignment: .leading, spacing: 13) {
                    MXLightSectionTitle(title: "新歌速递", onMore: onNew, moreLabel: "全部")
                    if songs.isEmpty {
                        ProgressView("正在加载新歌").tint(MXLight.teal)
                            .frame(maxWidth: .infinity, minHeight: 64)
                    } else {
                        ForEach(Array(songs.prefix(5).enumerated()), id: \.element.id) { index, track in
                            MXLightTrackRow(
                                track: track, index: index,
                                onPlay: { onSong(track.id) },
                                onFavorite: { onFavorite(track.id) },
                                favorite: isFavorite(track.id)
                            )
                        }
                    }
                }
                .padding(.top, 26)

                VStack(alignment: .leading, spacing: 13) {
                    MXLightSectionTitle(title: "精选专辑")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(Array(albums.prefix(8).enumerated()), id: \.element.id) { i, song in
                                Button { onAlbum(song.album, song.artist) } label: {
                                    VStack(alignment: .leading, spacing: 7) {
                                        MXLightArtwork(url: song.artworkURL, size: 142, variant: i)
                                        Text(song.album)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(MXLight.ink).lineLimit(1)
                                        Text(song.artist).font(.system(size: 12))
                                            .foregroundStyle(MXLight.muted).lineLimit(1)
                                    }
                                    .frame(width: 142, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.top, 26)

                VStack(alignment: .leading, spacing: 13) {
                    MXLightSectionTitle(title: "热门歌手")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(Array(artists.prefix(9).enumerated()), id: \.element.id) { i, track in
                                Button { onArtist(track.artist) } label: {
                                    VStack(spacing: 8) {
                                        MXLightArtwork(url: track.artworkURL, size: 73, variant: i)
                                            .clipShape(Circle())
                                        Text(track.artist).font(.system(size: 13))
                                            .foregroundStyle(MXLight.ink).lineLimit(1)
                                    }
                                    .frame(width: 73)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.top, 26)

                VStack(alignment: .leading, spacing: 13) {
                    MXLightSectionTitle(title: "推荐歌单", onMore: onAllCollections, moreLabel: "全部")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14),
                                       GridItem(.flexible(), spacing: 14)], spacing: 17) {
                        ForEach(Array(collections.prefix(12).enumerated()), id: \.element.id) { i, item in
                            Button { onCollection(item.id) } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    GeometryReader { proxy in
                                        MXLightArtwork(url: item.artworkURL, size: proxy.size.width, variant: i)
                                    }
                                    .aspectRatio(1, contentMode: .fit)
                                    Text(item.name).font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(MXLight.ink).lineLimit(2)
                                    if let count = item.count {
                                        Text("\(count) 首")
                                            .font(.system(size: 12)).foregroundStyle(MXLight.muted)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, 26)
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .background(MXLight.background)
    }

    private func promo(_ title: String, description: String, color: Color,
                       text: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.system(size: 17, weight: .bold))
                Text(description).font(.system(size: 11)).lineLimit(1)
            }
            .foregroundStyle(text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 97)
            .padding(.horizontal, 14)
            .background(color, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
}

struct MXLightSearch: View {
    @Binding var searchText: String
    let songs: [MXLightTrack]
    let isLoading: Bool
    let onScene: (String) -> Void
    let onSong: (Int) -> Void
    let isFavorite: (Int) -> Bool
    let onFavorite: (Int) -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                Text("搜索")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(MXLight.ink)
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass").foregroundStyle(MXLight.muted)
                    TextField("", text: $searchText,
                              prompt: Text("搜索歌曲、歌手或专辑").foregroundColor(MXLight.muted))
                        .font(.system(size: 15))
                        .foregroundStyle(MXLight.ink)
                        .tint(MXLight.red)
                        .autocorrectionDisabled()
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(MXLight.muted)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 13))

                if searchText.isEmpty {
                    MXLightSectionTitle(title: "音乐分类")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(Array(["华语流行", "经典老歌", "轻音乐", "纯音乐", "摇滚", "欧美音乐"].enumerated()), id: \.element) { index, name in
                            Button { onScene(name) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: ["music.note", "record.circle", "leaf", "pianokeys", "guitars", "headphones"][index])
                                        .font(.system(size: 19))
                                    Text(name).font(.system(size: 13, weight: .semibold))
                                }
                                .foregroundStyle(index % 2 == 0 ? MXLight.teal : MXLight.ink)
                                .frame(maxWidth: .infinity)
                                .frame(height: 82)
                                .background(index % 2 == 0 ? MXLight.ochre.opacity(0.27) : MXLight.teal.opacity(0.10),
                                            in: RoundedRectangle(cornerRadius: 16))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    MXLightSectionTitle(title: "热门搜索")
                    ForEach(["周杰伦", "陈奕迅", "晴天", "夜曲", "后来"], id: \.self) { keyword in
                        Button { searchText = keyword } label: {
                            HStack {
                                Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(MXLight.red)
                                Text(keyword).foregroundStyle(MXLight.ink)
                                Spacer()
                            }
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    MXLightSectionTitle(title: isLoading ? "正在搜索…" : "歌曲 · \(songs.count)")
                    ForEach(Array(songs.enumerated()), id: \.element.id) { i, song in
                        MXLightTrackRow(track: song, index: i,
                                        onPlay: { onSong(song.id) },
                                        onFavorite: { onFavorite(song.id) },
                                        favorite: isFavorite(song.id))
                    }
                    if songs.isEmpty && !isLoading {
                        Text("暂时没有匹配歌曲").font(.system(size: 14)).foregroundStyle(MXLight.muted)
                            .frame(maxWidth: .infinity).padding(.vertical, 30)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 24)
        }
        .background(MXLight.background)
    }
}

struct MXLightLibrary: View {
    @Binding var segment: String
    let recent: [MXLightTrack]
    let favorites: [MXLightTrack]
    let playlists: [MXLightCollection]
    let onSong: (Int, String) -> Void
    let onFavorite: (Int) -> Void
    let onPlaylist: (String) -> Void
    let onImport: () -> Void
    let onSettings: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("音乐库").font(.system(size: 32, weight: .bold))
                    Spacer()
                    Button(action: onSettings) { Image(systemName: "ellipsis.circle").font(.system(size: 24)) }
                        .accessibilityLabel("音乐库设置")
                }
                .foregroundStyle(MXLight.ink)
                VStack(spacing: 0) {
                    shortcut("最近播放", symbol: "clock", count: recent.count, value: "recent")
                    Divider().overlay(MXLight.line)
                    shortcut("收藏歌曲", symbol: "heart", count: favorites.count, value: "favorites")
                    Divider().overlay(MXLight.line)
                    shortcut("我的歌单", symbol: "music.note.list", count: playlists.count, value: "playlists")
                }
                .padding(.horizontal, 17)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 18))

                HStack(spacing: 10) {
                    ForEach(["recent", "favorites", "playlists"], id: \.self) { value in
                        Button(label(value)) { segment = value }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(segment == value ? .white : MXLight.muted)
                            .frame(maxWidth: .infinity)
                            .frame(height: 37)
                            .background(segment == value ? MXLight.teal : MXLight.paper, in: Capsule())
                    }
                }

                if segment == "playlists" {
                    HStack {
                        MXLightSectionTitle(title: "我的歌单")
                        Button(action: onImport) {
                            Image(systemName: "plus").font(.system(size: 18)).foregroundStyle(MXLight.red)
                        }
                    }
                    ForEach(Array(playlists.enumerated()), id: \.element.id) { i, item in
                        Button { onPlaylist(item.id) } label: {
                            HStack(spacing: 12) {
                                MXLightArtwork(url: item.artworkURL, size: 62, variant: i)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(MXLight.ink)
                                    Text("\(item.count ?? 0) 首歌曲").font(.system(size: 12)).foregroundStyle(MXLight.muted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(MXLight.muted)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    let visible = segment == "favorites" ? favorites : recent
                    MXLightSectionTitle(title: segment == "favorites" ? "收藏歌曲" : "最近播放")
                    if visible.isEmpty {
                        Text("这里还没有音乐").foregroundStyle(MXLight.muted).padding(.vertical, 22)
                    } else {
                        ForEach(Array(visible.enumerated()), id: \.element.id) { i, song in
                            MXLightTrackRow(track: song, index: i, onPlay: { onSong(song.id, segment) },
                                            onFavorite: { onFavorite(song.id) },
                                            favorite: favorites.contains(where: { $0.id == song.id }))
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 24)
        }
        .background(MXLight.background)
    }

    private func label(_ value: String) -> String {
        switch value {
        case "favorites": "收藏"
        case "playlists": "歌单"
        default: "最近"
        }
    }

    private func shortcut(_ title: String, symbol: String, count: Int, value: String) -> some View {
        Button { segment = value } label: {
            HStack(spacing: 13) {
                Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(MXLight.red).frame(width: 27)
                Text(title).font(.system(size: 16, weight: .medium)).foregroundStyle(MXLight.ink)
                Spacer()
                Text("\(count)").foregroundStyle(MXLight.muted)
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(MXLight.muted)
            }
            .frame(height: 58)
        }
        .buttonStyle(.plain)
    }
}

/// Reused by both the main tabs and every light-themed detail route.
struct MXLightMiniPlayer: View {
    let now: MXLightTrack
    let isPlaying: Bool
    let isResolving: Bool
    let onPlayer: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onPlayer) {
                HStack(spacing: 10) {
                    MXLightArtwork(url: now.artworkURL, size: 42)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(now.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(MXLight.ink).lineLimit(1)
                        Text(now.artist)
                            .font(.system(size: 11))
                            .foregroundStyle(MXLight.muted).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }.buttonStyle(.plain)
            Button(action: onPlayPause) {
                Group {
                    if isResolving { ProgressView().tint(MXLight.teal) }
                    else { Image(systemName: isPlaying ? "pause.fill" : "play.fill") }
                }
                .frame(width: 36, height: 42)
            }
            Button(action: onNext) {
                Image(systemName: "forward.end.fill")
                    .frame(width: 34, height: 42)
            }
        }
        .foregroundStyle(MXLight.ink)
        .padding(.horizontal, 11)
        .frame(height: 60)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(.white.opacity(0.8), lineWidth: 0.8))
        .shadow(color: MXLight.ink.opacity(0.10), radius: 9, y: 3)
        .padding(.horizontal, 12)
    }
}

struct MXLightChrome: View {
    let selectedTab: String
    let onTab: (String) -> Void
    let now: MXLightTrack?
    let isPlaying: Bool
    let isResolving: Bool
    let onPlayer: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if let now {
                MXLightMiniPlayer(now: now, isPlaying: isPlaying, isResolving: isResolving,
                                  onPlayer: onPlayer, onPlayPause: onPlayPause, onNext: onNext)
            }
            HStack(spacing: 5) {
                tab("首页", icon: "house")
                tab("搜索", icon: "magnifyingglass")
                tab("音乐库", icon: "music.note")
            }
            .padding(7)
            .frame(height: 64)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule().stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.98), .white.opacity(0.25)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ), lineWidth: 1.2
                        )
                    }
            }
            .overlay(Capsule().stroke(MXLight.teal.opacity(0.13), lineWidth: 0.7))
            .shadow(color: MXLight.teal.opacity(0.14), radius: 12, y: 4)
            .padding(.horizontal, 20)
        }
        .padding(.top, 6)
        .padding(.bottom, 3)
        .background(MXLight.background.opacity(0.15))
    }

    private func tab(_ name: String, icon: String) -> some View {
        let active = selectedTab == name
        let symbol = active && name == "搜索" ? "magnifyingglass.circle.fill"
                    : active ? icon + ".fill" : icon
        return Button { onTab(name) } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: active ? .semibold : .regular))
                    .frame(height: 26)
                Text(name).font(.system(size: 11, weight: active ? .bold : .medium))
            }
            .foregroundStyle(active ? MXLight.teal : MXLight.muted)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(active ? MXLight.ochre.opacity(0.38) : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

struct MXLightSettings: View {
    @Binding var appearance: String
    let onQuality: () -> Void
    let onSources: () -> Void
    let onBackup: () -> Void
    let onRestore: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("外观主题") {
                    Picker("外观主题", selection: $appearance) {
                        Text("经典深色版").tag("classic")
                        Text("暖色浅色版").tag("light")
                    }
                    .pickerStyle(.inline)
                }
                Section("播放") {
                    Button("音质设置", action: onQuality)
                }
                Section("音乐数据") {
                    Button("备份音乐收藏", action: onBackup)
                    Button("恢复音乐收藏", action: onRestore)
                }
                Section("高级功能") {
                    Button("音源管理", action: onSources)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.light)
    }
}
