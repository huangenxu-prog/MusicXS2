import SwiftUI
import AVKit

/// Reproduction of the 14-page MusicX reference: 04 player / 05 lyrics / 06 queue.
/// All playback actions operate on the existing shared PlayerStore.
struct MXReferencePlayer: View {
    let song: MXLightTrack?
    let queue: [MXLightTrack]
    let lyrics: [String]
    let activeLyricIndex: Int
    let lyricsUnavailable: Bool
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
    let onMoveQueue: (IndexSet, Int) -> Void
    let onQuality: () -> Void
    let onSleepTimer: () -> Void

    @State private var isScrubbing = false
    @State private var scrubPosition: Double = 0
    @State private var showingClearQueueConfirmation = false

    var body: some View {
        GeometryReader { geom in
            Group {
                switch mode {
                case "lyrics": lyricPage
                case "queue": queuePage
                default: playerPage(size: geom.size)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MXLight.background.ignoresSafeArea())
        }
        .preferredColorScheme(.light)
        .simultaneousGesture(
            DragGesture(minimumDistance: 24, coordinateSpace: .global)
                .onEnded { gesture in
                    let dx = gesture.translation.width
                    let dy = gesture.translation.height
                    if gesture.startLocation.x <= 36 && dx > 85 && dx > abs(dy) * 1.3 {
                        if mode == "artwork" { onClose() } else { mode = "artwork" }
                    } else if gesture.startLocation.y <= 140 && dy > 110 && dy > abs(dx) * 1.35 {
                        onClose()
                    }
                }
        )
    }

    private func header(_ title: String, back: @escaping () -> Void) -> some View {
        HStack {
            Button(action: back) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 19, weight: .regular))
                    .frame(width: 40, height: 44, alignment: .leading)
            }
            Spacer()
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .tracking(2)
                .foregroundStyle(MXLight.muted)
            Spacer()
            Menu {
                Button("封面", systemImage: "square") { mode = "artwork" }
                Button("歌词", systemImage: "text.alignleft") { mode = "lyrics" }
                Button("播放队列", systemImage: "list.bullet") { mode = "queue" }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 21, weight: .semibold))
                    .frame(width: 40, height: 44, alignment: .trailing)
                    .foregroundStyle(MXLight.ink)
            }
        }
        .foregroundStyle(MXLight.ink)
        .padding(.horizontal, 24)
    }

    private func playerPage(size: CGSize) -> some View {
        let coverSize = max(175, min(304, size.width - 48, size.height * 0.41))
        return VStack(spacing: 0) {
            header("正 在 播 放", back: onClose)
            Spacer(minLength: 8)

            MXLightArtwork(url: song?.artworkURL, size: coverSize, variant: 2)
                .shadow(color: MXLight.ink.opacity(0.17), radius: 20, y: 13)
                .frame(maxWidth: .infinity)

            Spacer(minLength: 16)
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(song?.title ?? "尚未播放")
                        .font(.system(size: 27, weight: .heavy))
                        .foregroundStyle(MXLight.ink)
                        .lineLimit(1)
                    Text([song?.artist, song?.album].compactMap { $0?.isEmpty == false ? $0 : nil }
                        .joined(separator: " · "))
                        .font(.system(size: 15))
                        .foregroundStyle(MXLight.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Button(action: onFavorite) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 27, weight: .regular))
                        .foregroundStyle(MXLight.red)
                        .frame(width: 42, height: 50)
                }
                .disabled(song == nil)
            }
            .padding(.horizontal, 28)

            timeline
                .padding(.horizontal, 27)
                .padding(.top, 25)

            HStack(spacing: 0) {
                Button(action: onShuffle) {
                    Image(systemName: "shuffle")
                        .foregroundStyle(shuffle ? MXLight.red : MXLight.ink)
                }
                .accessibilityLabel(shuffle ? "关闭随机播放" : "开启随机播放")
                Spacer()
                Button(action: onPrevious) {
                    Image(systemName: "backward.end.fill").foregroundStyle(MXLight.ink)
                }
                Spacer()
                Button(action: onPlayPause) {
                    Group {
                        if isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 27, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 65, height: 65)
                    .background(MXLight.ink, in: Circle())
                }
                .disabled(song == nil)
                Spacer()
                Button(action: onNext) {
                    Image(systemName: "forward.end.fill").foregroundStyle(MXLight.ink)
                }
                Spacer()
                Button(action: onRepeat) {
                    Image(systemName: repeatMode == 2 ? "repeat.1" : "repeat")
                        .foregroundStyle(repeatMode == 0 ? MXLight.ink : MXLight.red)
                }
                .accessibilityLabel(repeatMode == 2 ? "单曲循环" :
                                    repeatMode == 1 ? "列表循环" : "不循环")
            }
            .font(.system(size: 21))
            .padding(.horizontal, 36)
            .frame(height: 106)

            HStack(spacing: 0) {
                footerButton("歌词", icon: "text.alignleft") { mode = "lyrics" }
                footerButton("播放队列", icon: "list.bullet") { mode = "queue" }
                footerButton("睡眠定时", icon: "moon.zzz", action: onSleepTimer)
                footerButton("音质", icon: "gearshape", action: onQuality)
            }
            .padding(.horizontal, 12)
            .frame(height: 76)
            .padding(.bottom, 10)
        }
    }

    private func footerButton(_ title: String, icon: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .regular))
                    .frame(height: 25)
                Text(title).font(.system(size: 11))
            }
            .foregroundStyle(MXLight.muted)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var timeline: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: {
                        isScrubbing ? scrubPosition :
                        min(max(currentTime, 0), max(duration, 1))
                    },
                    set: { scrubPosition = $0 }),
                in: 0...max(1, duration),
                onEditingChanged: { isEditing in
                    if isEditing {
                        scrubPosition = currentTime
                        isScrubbing = true
                    } else {
                        isScrubbing = false
                        onSeek(scrubPosition)
                    }
                })
            .tint(MXLight.red)
            .disabled(duration <= 0)
            HStack {
                Text(time(isScrubbing ? scrubPosition : currentTime))
                Spacer()
                Text(time(duration))
            }
            .font(.system(size: 12))
            .foregroundStyle(MXLight.muted)
            .monospacedDigit()
        }
    }

    private var lyricPage: some View {
        VStack(spacing: 0) {
            header("歌词") { mode = "artwork" }
            HStack(spacing: 12) {
                MXLightArtwork(url: song?.artworkURL, size: 54, variant: 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(song?.title ?? "尚未播放")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(MXLight.ink)
                    Text(song?.artist ?? "")
                        .font(.system(size: 12)).foregroundStyle(MXLight.muted)
                }
                Spacer()
            }
            .padding(.horizontal, 26)
            .padding(.top, 24)

            ScrollViewReader { reader in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 25) {
                        if lyrics.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(lyricsUnavailable ? "暂时没有找到歌词" : "正在获取歌词…")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundStyle(MXLight.muted)
                                if !lyricsUnavailable {
                                    ProgressView().tint(MXLight.teal)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(Array(lyrics.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(size: index == activeLyricIndex ? 25 : 21,
                                                  weight: index == activeLyricIndex ? .semibold : .medium))
                                    .foregroundStyle(index == activeLyricIndex ? MXLight.red :
                                                     index < activeLyricIndex ? MXLight.ink.opacity(0.77) :
                                                     MXLight.ink.opacity(0.67))
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(index)
                            }
                        }
                    }
                    .padding(.horizontal, 30)
                    .padding(.vertical, 45)
                }
                .onChange(of: activeLyricIndex) { _, index in
                    guard lyrics.indices.contains(index) else { return }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        reader.scrollTo(index, anchor: .center)
                    }
                }
            }

            timeline
                .padding(.horizontal, 27)
            HStack(spacing: 43) {
                Button(action: onPrevious) { Image(systemName: "backward.end.fill") }
                Button(action: onPlayPause) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 23))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(MXLight.ink, in: Circle())
                }
                Button(action: onNext) { Image(systemName: "forward.end.fill") }
            }
            .font(.system(size: 20))
            .foregroundStyle(MXLight.ink)
            .padding(.top, 13)
            .padding(.bottom, 20)
        }
    }

    private var queuePage: some View {
        VStack(spacing: 0) {
            header("播放队列") { mode = "artwork" }
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("接下来播放")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(MXLight.ink)
                    Text("共 \(upNext.count) 首 · 长按把手调整顺序")
                        .font(.system(size: 12))
                        .foregroundStyle(MXLight.muted)
                }
                Spacer()
                Button {
                    showingClearQueueConfirmation = true
                } label: {
                    Label("清空", systemImage: "trash")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MXLight.red)
                        .frame(minWidth: 62, minHeight: 44)
                }
                .disabled(upNext.isEmpty)
                .accessibilityLabel("清空待播放歌曲")
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 12)
            MXLight.line.frame(height: 0.5)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if let song {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("正在播放")
                                .font(.system(size: 12))
                                .foregroundStyle(MXLight.muted)
                            HStack(spacing: 11) {
                                MXLightArtwork(url: song.artworkURL, size: 48, variant: 2)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(song.title)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(MXLight.red)
                                        .lineLimit(1)
                                    Text(song.artist)
                                        .font(.system(size: 12)).foregroundStyle(MXLight.muted)
                                }
                                Spacer()
                                Text(time(song.duration ?? duration))
                                    .font(.system(size: 12)).foregroundStyle(MXLight.muted)
                            }
                        }
                        .padding(15)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(MXLight.cream, in: RoundedRectangle(cornerRadius: 16))
                    }
                     List {
                        ForEach(Array(upNext.enumerated()), id: \.element.id) { index, track in
                            Button { onQueuePlay(track.id) } label: {
                                HStack(spacing: 11) {
                                    MXLightArtwork(url: track.artworkURL, size: 48, variant: index)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(track.title)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(MXLight.ink).lineLimit(1)
                                        Text(track.artist)
                                            .font(.system(size: 12)).foregroundStyle(MXLight.muted)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Menu {
                                        Button("播放", systemImage: "play.fill") { onQueuePlay(track.id) }
                                        Button("从队列移除", systemImage: "trash", role: .destructive) {
                                            onRemoveQueue(track.id)
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis")
                                            .foregroundStyle(MXLight.muted)
                                            .frame(width: 26, height: 42)
                                    }
                                }
                            }
                            .listRowBackground(MXLight.background)
                            .listRowSeparator(.hidden)
                        }
                        .onMove(perform: onMoveQueue)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .environment(\.editMode, .constant(.active))
                    .frame(height: CGFloat(upNext.count) * 63 + 10)
                    .scrollDisabled(true)

                 }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 22)
            }
        }
        .confirmationDialog("清空待播队列？",
                            isPresented: $showingClearQueueConfirmation,
                            titleVisibility: .visible) {
            Button("清空待播歌曲", role: .destructive, action: onClearQueue)
            Button("取消", role: .cancel) {}
        } message: {
            Text("仅清除待播放歌曲，不停止当前歌曲。")
        }
    }

    private var upNext: [MXLightTrack] {
        queue.filter { $0.id != song?.id }
    }

    private func time(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "0:00" }
        let n = Int(value)
        return String(format: "%d:%02d", n / 60, n % 60)
    }
}

struct MXReferencePill: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isPrimary ? .white : MXLight.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 43)
            .background(isPrimary ? MXLight.red : MXLight.cream, in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct MXLightAirPlayPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView(frame: .zero)
        picker.tintColor = UIColor(red: 117/255, green: 111/255, blue: 101/255, alpha: 1)
        picker.activeTintColor = UIColor(red: 217/255, green: 72/255, blue: 43/255, alpha: 1)
        picker.prioritizesVideoDevices = false
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
