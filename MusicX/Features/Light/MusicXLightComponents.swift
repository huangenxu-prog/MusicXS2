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
    var source: MusicSource? = nil
}

struct MXLightCollection: Identifiable {
    let id: String
    let name: String
    let count: Int?
    let artworkURL: URL?
    var source: MusicSource? = nil
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
    let playlists: [MXLightCollection]
    let isLoading: Bool
    let onScene: (String) -> Void
    let onSong: (Int) -> Void
    let isFavorite: (Int) -> Bool
    let onFavorite: (Int) -> Void
    let onAlbum: (String, String) -> Void
    let onArtist: (String) -> Void
    let onPlaylist: (String) -> Void
    @State private var selectedSource = "全部来源"
    @State private var showAllSongs = false

    private var visibleSongs: [MXLightTrack] {
        switch selectedSource {
        case "QQ 音乐": songs.filter { $0.source == .qq }
        case "网易云": songs.filter { $0.source == .netease }
        default: songs
        }
    }
    private var visiblePlaylists: [MXLightCollection] {
        switch selectedSource {
        case "QQ 音乐": playlists.filter { $0.source == .qq }
        case "网易云": playlists.filter { $0.source == .netease }
        default: playlists
        }
    }
    private var artists: [MXLightTrack] {
        var seen = Set<String>()
        return visibleSongs.filter { !$0.artist.isEmpty && seen.insert($0.artist).inserted }
    }
    private var albums: [MXLightTrack] {
        var seen = Set<String>()
        return visibleSongs.filter {
            !$0.album.isEmpty && seen.insert($0.album + "|" + $0.artist).inserted
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("搜索")
                        .font(.system(size: 30, weight: .heavy))
                        .foregroundStyle(MXLight.ink)
                    Spacer()
                    Image(systemName: "clock")
                        .font(.system(size: 23))
                        .foregroundStyle(MXLight.ink)
                        .frame(width: 38, height: 38)
                }
                .padding(.bottom, 23)

                HStack(spacing: 11) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20))
                        .foregroundStyle(MXLight.ink)
                    TextField("", text: $searchText,
                              prompt: Text("搜索歌曲、歌手、专辑、歌单")
                                .foregroundColor(MXLight.muted))
                        .font(.system(size: 15))
                        .foregroundStyle(MXLight.ink)
                        .tint(MXLight.red)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: searchText) { _, _ in showAllSongs = false }
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16))
                                .foregroundStyle(MXLight.muted)
                                .frame(width: 28, height: 36)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 46)
                .background(MXLight.cream, in: Capsule())

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        ForEach(["全部来源", "QQ 音乐", "网易云"], id: \.self) { name in
                            Button { selectedSource = name } label: {
                                Text(name)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(selectedSource == name ? .white : MXLight.ink)
                                    .padding(.horizontal, 17)
                                    .frame(height: 40)
                                    .background(selectedSource == name ? MXLight.ink : MXLight.cream, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, 13)

                if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    MXLightSectionTitle(title: "热门搜索")
                        .padding(.top, 29)
                    ForEach(["周杰伦", "陈奕迅", "晴天", "夜曲", "后来"], id: \.self) { term in
                        Button { searchText = term } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 12))
                                    .foregroundStyle(MXLight.red)
                                Text(term).foregroundStyle(MXLight.ink)
                                Spacer()
                            }
                            .font(.system(size: 15))
                            .padding(.vertical, 13)
                        }.buttonStyle(.plain)
                    }
                    MXLightSectionTitle(title: "音乐分类").padding(.top, 24)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                        GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(Array(["华语流行","经典老歌","轻音乐","纯音乐","摇滚","欧美音乐"].enumerated()),
                                id: \.element) { i, item in
                            Button { onScene(item) } label: {
                                VStack(alignment: .leading, spacing: 12) {
                                    Image(systemName: ["music.note","opticaldisc","leaf","pianokeys",
                                                       "guitars","headphones"][i])
                                        .font(.system(size: 23))
                                    Text(item).font(.system(size: 14, weight: .semibold))
                                }
                                .foregroundStyle(i % 2 == 0 ? MXLight.teal : MXLight.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: 84)
                                .padding(.horizontal, 15)
                                .background(i % 2 == 0 ? MXLight.ochre.opacity(0.27) :
                                            MXLight.lightTeal,
                                            in: RoundedRectangle(cornerRadius: 18))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 14)
                } else {
                    MXLightSectionTitle(title: "歌曲")
                        .padding(.top, 29)
                    if isLoading && visibleSongs.isEmpty {
                        ProgressView("正在搜索").tint(MXLight.teal)
                            .frame(maxWidth: .infinity, minHeight: 85)
                    }
                    ForEach(Array((showAllSongs ? visibleSongs : Array(visibleSongs.prefix(4))).enumerated()),
                            id: \.element.id) { i, song in
                        HStack(spacing: 0) {
                            MXLightTrackRow(
                                track: song, index: i,
                                onPlay: { onSong(song.id) },
                                onFavorite: { onFavorite(song.id) },
                                favorite: isFavorite(song.id))
                            if let src = song.source {
                                Text(src == .qq ? "QQ 音乐" : src == .netease ? "网易云" : src.displayName)
                                    .font(.system(size: 10))
                                    .foregroundStyle(MXLight.muted)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 5)
                                    .background(MXLight.cream, in: RoundedRectangle(cornerRadius: 5))
                            }
                        }
                    }
                    if visibleSongs.count > 4 && !showAllSongs {
                        Button { showAllSongs = true } label: {
                            Text("查看全部歌曲")
                                .font(.system(size: 14))
                                .foregroundStyle(MXLight.ink)
                                .frame(maxWidth: .infinity)
                                .frame(height: 42)
                                .background(MXLight.cream, in: Capsule())
                        }
                        .padding(.top, 5)
                        .buttonStyle(.plain)
                    }

                    if !artists.isEmpty {
                        MXLightSectionTitle(title: "歌手").padding(.top, 27)
                        ForEach(Array(artists.prefix(5).enumerated()), id: \.element.id) { i, track in
                            Button { onArtist(track.artist) } label: {
                                HStack(spacing: 12) {
                                    MXLightArtwork(url: track.artworkURL, size: 48, variant: i)
                                        .clipShape(Circle())
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(track.artist).font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(MXLight.ink)
                                        Text("歌手").font(.system(size: 12)).foregroundStyle(MXLight.muted)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(MXLight.muted)
                                }.padding(.vertical, 6)
                            }.buttonStyle(.plain)
                        }
                    }
                    if !albums.isEmpty {
                        MXLightSectionTitle(title: "专辑").padding(.top, 27)
                        ForEach(Array(albums.prefix(5).enumerated()), id: \.element.id) { i, track in
                            Button { onAlbum(track.album, track.artist) } label: {
                                HStack(spacing: 12) {
                                    MXLightArtwork(url: track.artworkURL, size: 48, variant: i+3)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(track.album).font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(MXLight.ink).lineLimit(1)
                                        Text(track.artist).font(.system(size: 12)).foregroundStyle(MXLight.muted)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(MXLight.muted)
                                }.padding(.vertical, 6)
                            }.buttonStyle(.plain)
                        }
                    }
                    if !visiblePlaylists.isEmpty {
                        MXLightSectionTitle(title: "歌单").padding(.top, 27)
                        ForEach(Array(visiblePlaylists.prefix(5).enumerated()), id: \.element.id) { i, item in
                            Button { onPlaylist(item.id) } label: {
                                HStack(spacing: 12) {
                                    MXLightArtwork(url: item.artworkURL, size: 48, variant: i)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.name).font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(MXLight.ink).lineLimit(1)
                                        if let count = item.count {
                                            Text("\(count) 首").font(.system(size: 12)).foregroundStyle(MXLight.muted)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(MXLight.muted)
                                }.padding(.vertical, 6)
                            }.buttonStyle(.plain)
                        }
                    }
                    if !isLoading && visibleSongs.isEmpty && visiblePlaylists.isEmpty {
                        Text("暂时没有搜索结果")
                            .font(.system(size: 14))
                            .foregroundStyle(MXLight.muted)
                            .frame(maxWidth: .infinity).padding(.top, 25)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 30)
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
    let onSearch: () -> Void
    let onSettings: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("音乐库")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(MXLight.ink)
                        Text("所有喜欢的音乐，都在这里")
                            .font(.system(size: 13))
                            .foregroundStyle(MXLight.muted)
                    }
                    Spacer()
                    Button(action: onSearch) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 22)).frame(width: 40, height: 40)
                    }
                    Button(action: onSettings) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 22)).frame(width: 40, height: 40)
                    }
                }
                .foregroundStyle(MXLight.ink)
                .padding(.bottom, 23)

                VStack(spacing: 0) {
                    shortcut("最近播放", icon: "clock", count: recent.count, value: "recent")
                    MXLight.line.frame(height: 0.5)
                    shortcut("收藏歌曲", icon: "heart", count: favorites.count, value: "favorites")
                    MXLight.line.frame(height: 0.5)
                    shortcut("我的歌单", icon: "list.bullet", count: playlists.count, value: "playlists")
                }
                .padding(.horizontal, 15)
                .background(MXLight.paper, in: RoundedRectangle(cornerRadius: 18))

                HStack {
                    MXLightSectionTitle(title: segment == "playlists" ? "我的歌单"
                                        : segment == "recent" ? "最近播放" : "收藏歌曲")
                    Spacer()
                    if segment != "playlists" {
                        Button("返回歌单") { segment = "playlists" }
                            .font(.system(size: 12)).foregroundStyle(MXLight.muted)
                    } else {
                        Button(action: onImport) {
                            Label("导入", systemImage: "plus").font(.system(size: 12))
                                .foregroundStyle(MXLight.red)
                        }
                    }
                }
                .padding(.top, 27)
                .padding(.bottom, 14)

                if segment == "playlists" {
                    if playlists.isEmpty {
                        Button(action: onImport) {
                            Label("导入 QQ 音乐或网易云歌单", systemImage: "plus")
                                .font(.system(size: 14))
                                .foregroundStyle(MXLight.teal)
                                .frame(maxWidth: .infinity, minHeight: 100)
                                .background(MXLight.cream, in: RoundedRectangle(cornerRadius: 18))
                        }
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14),
                                            GridItem(.flexible(), spacing: 14)], spacing: 16) {
                            ForEach(Array(playlists.enumerated()), id: \.element.id) { index, item in
                                Button { onPlaylist(item.id) } label: {
                                    VStack(alignment: .leading, spacing: 7) {
                                        GeometryReader { proxy in
                                            MXLightArtwork(url: item.artworkURL,
                                                           size: proxy.size.width, variant: index)
                                        }
                                        .aspectRatio(1, contentMode: .fit)
                                        Text(item.name)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(MXLight.ink).lineLimit(2)
                                        Text("\(item.source?.displayName ?? "歌单") · \(item.count ?? 0) 首")
                                            .font(.system(size: 12))
                                            .foregroundStyle(MXLight.muted).lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                } else {
                    let visible = segment == "favorites" ? favorites : recent
                    if visible.isEmpty {
                        Text("这里还没有音乐")
                            .font(.system(size: 14)).foregroundStyle(MXLight.muted)
                            .padding(.vertical, 26)
                    } else {
                        ForEach(Array(visible.enumerated()), id: \.element.id) { i, track in
                            MXLightTrackRow(track: track, index: i,
                                            onPlay: { onSong(track.id, segment) },
                                            onFavorite: { onFavorite(track.id) },
                                            favorite: favorites.contains { $0.id == track.id })
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 30)
        }
        .background(MXLight.background)
    }

    private func shortcut(_ title: String, icon: String, count: Int, value: String) -> some View {
        Button { segment = value } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundStyle(value == "favorites" ? MXLight.red : MXLight.muted)
                    .frame(width: 34, height: 34)
                    .background(MXLight.cream, in: Circle())
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MXLight.ink)
                Spacer()
                Text("\(count) 首")
                    .font(.system(size: 12))
                    .foregroundStyle(MXLight.muted)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
                    .foregroundStyle(MXLight.muted)
            }
            .frame(height: 57)
        }.buttonStyle(.plain)
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
    let onImportPlaylist: () -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("musicx.repeatMode") private var repeatMode = 0
    @AppStorage("musicx.playbackQuality") private var qualityRaw = MusicQuality.high.rawValue

    private var qualityName: String {
        switch MusicQuality(rawValue: qualityRaw) ?? .high {
        case .standard: return "标准 128 kbps"
        case .high: return "高音质 320 kbps"
        case .lossless: return "无损"
        case .hires: return "Hi-Res"
        }
    }
    private var orderName: String {
        switch repeatMode {
        case 1: return "列表循环"
        case 2: return "单曲循环"
        default: return "顺序播放"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 19)).frame(width: 40, height: 42, alignment: .leading)
                }
                Spacer()
                Text("更多").font(.system(size: 16, weight: .bold))
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 20))
                    .frame(width: 40, height: 42, alignment: .trailing)
            }
            .foregroundStyle(MXLight.ink)
            .padding(.horizontal, 24)
            .padding(.top, 6)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    sectionLabel("播放体验")
                    card {
                        row("音质选择", icon: "speaker.wave.2", hint: qualityName,
                            action: onQuality)
                        MXLight.line.frame(height: 0.5)
                        row("播放顺序", icon: "repeat", hint: orderName) {
                            repeatMode = (repeatMode + 1) % 3
                        }
                    }

                    sectionLabel("音乐数据")
                    card {
                        row("导入歌单", icon: "square.and.arrow.down",
                            action: onImportPlaylist)
                        MXLight.line.frame(height: 0.5)
                        row("导出音乐收藏", icon: "square.and.arrow.up",
                            action: onBackup)
                        MXLight.line.frame(height: 0.5)
                        row("恢复音乐收藏", icon: "square.and.arrow.down",
                            action: onRestore)
                    }

                    sectionLabel("外观")
                    card {
                        HStack(spacing: 12) {
                            Image(systemName: "paintbrush")
                                .font(.system(size: 17))
                                .frame(width: 34, height: 34)
                                .background(MXLight.cream, in: Circle())
                            Text("外观主题")
                                .font(.system(size: 15, weight: .semibold))
                            Spacer()
                            Picker("外观主题", selection: $appearance) {
                                Text("经典深色版").tag("classic")
                                Text("暖色浅色版").tag("light")
                            }
                            .tint(MXLight.teal)
                            .labelsHidden()
                        }
                        .foregroundStyle(MXLight.ink)
                        .frame(height: 57)
                    }

                    sectionLabel("高级功能")
                    card {
                        row("音源管理", icon: "lock",
                            hint: "需要暗号", action: onSources)
                    }

                    Text("MusicX · 无需账号 · 专注听歌")
                        .font(.system(size: 12))
                        .foregroundStyle(MXLight.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 32)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 30)
            }
        }
        .background(MXLight.background.ignoresSafeArea())
        .preferredColorScheme(.light)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .tracking(1.8)
            .foregroundStyle(MXLight.muted)
            .padding(.top, 25)
            .padding(.bottom, 11)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .padding(.horizontal, 15)
            .background(MXLight.paper, in: RoundedRectangle(cornerRadius: 18))
    }

    private func row(_ title: String, icon: String, hint: String? = nil,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundStyle(MXLight.ink)
                    .frame(width: 34, height: 34)
                    .background(MXLight.cream, in: Circle())
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MXLight.ink)
                Spacer(minLength: 6)
                if let hint {
                    Text(hint)
                        .font(.system(size: 12))
                        .foregroundStyle(MXLight.muted)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
                    .foregroundStyle(MXLight.ink)
            }
            .frame(height: 57)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
