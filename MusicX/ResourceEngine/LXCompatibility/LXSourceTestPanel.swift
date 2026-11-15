import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

/// Temporary test-only UI. Does not affect the normal music resource scheduler.
struct LXSourceTestPanel: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isImporterPresented = false
    @State private var importedIDs: [String] = []
    @State private var message: String?
    @State private var selectedID: String?
    @State private var library: LXSourceLibrary?
    @State private var searchResults: [MusicSong] = []
    @State private var selectedSong: MusicSong?
    @State private var isSearching = false
    @State private var testSongName = ""
    @State private var testPlatform = "tx"
    @State private var testArtist = ""
    @State private var isResolving = false
    @State private var activeHost: LXSourceScriptHost?
    @State private var previewPlayer: AVPlayer?
    @State private var previewURL: URL?
    @State private var previewDiagnosticTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                Section("测试音源") {
                    if importedIDs.isEmpty {
                        Text("尚未导入 JS 音源").foregroundStyle(.secondary)
                    }
                    ForEach(importedIDs, id: \.self) { id in
                        HStack {
                            Button {
                                do {
                                    try getLibrary().select(id: id)
                                    selectedID = id
                                    message = "已切换测试音源。尚未接入正式播放。"
                                } catch { message = error.localizedDescription }
                            } label: {
                                HStack {
                                    Image(systemName: selectedID == id ? "largecircle.fill.circle" : "circle")
                                        .foregroundStyle(selectedID == id ? .green : .secondary)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text((try? getLibrary().filename(id: id)) ?? id).lineLimit(1)
                                        Text(selectedID == id ? "当前选中 · 未接入正式播放" : "点击切换为当前测试音源")
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            Button("检查") { inspect(id: id) }
                                .buttonStyle(.bordered)
                        }
                    }
                    .onDelete(perform: delete)
                }
                Section {
                    Text("可导入多个音源，点击左侧圆圈切换当前测试音源。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("从文件导入 .js 音源") { isImporterPresented = true }
                }
                Section("多平台歌曲搜索与试听") {
                    Picker("平台", selection: $testPlatform) {
                        Text("QQ").tag("tx")
                        Text("网易").tag("wy")
                        Text("酷我").tag("kw")
                        Text("酷狗").tag("kg")
                    }
                    .onChange(of: testPlatform) { _, _ in
                        searchResults = []
                        selectedSong = nil
                        previewPlayer?.pause()
                        previewPlayer = nil
                        previewURL = nil
                    }
                    TextField("歌曲名称", text: $testSongName)
                    TextField("歌手名称（可选）", text: $testArtist)
                    Button(isSearching ? "搜索中…" : "搜索歌曲") {
                        Task { await searchPlatform() }
                    }
                    .disabled(isSearching || testSongName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    ForEach(searchResults) { song in
                        Button {
                            selectedSong = song
                            Task { await resolveSelectedSong() }
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(song.title)
                                Text(song.artist).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .disabled(isResolving || selectedID == nil)
                    }
                    if isResolving { ProgressView("正在解析选中的歌曲…") }
                    if previewURL != nil {
                        Button(previewPlayer == nil ? "试听解析结果" : "停止试听") { togglePreview() }
                    }
                    Text("选择平台后搜索并取链。搜索仍使用现有服务，尚未移植洛雪原生搜索模块。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let message {
                    Section("测试结果") { Text(message).font(.footnote).textSelection(.enabled) }
                }
            }
            .navigationTitle("音源测试")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } } }
            .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.plainText, .data], allowsMultipleSelection: true) { result in
                do {
                    let files = try result.get()
                    let library = try getLibrary()
                    var imported: [String] = []
                    var failed: [String] = []
                    for file in files {
                        do { imported.append(try library.importScript(from: file).filename) }
                        catch { failed.append("\(file.lastPathComponent): \(error.localizedDescription)") }
                    }
                    reload()
                    message = "已导入 \(imported.count) 个音源。\(failed.isEmpty ? "" : "失败：\(failed.joined(separator: "；"))")"
                } catch { message = "导入失败：\(error.localizedDescription)" }
            }
            .onAppear { reload() }
            .onDisappear { stopPreview() }
        }
    }

    @MainActor
    private func getLibrary() throws -> LXSourceLibrary {
        if let library { return library }
        let newLibrary = try LXSourceLibrary()
        library = newLibrary
        return newLibrary
    }

    private func reload() {
        do {
            let store = try getLibrary()
            importedIDs = try store.listIdentifiers()
            selectedID = store.selectedID
        }
        catch { message = "读取失败：\(error.localizedDescription)" }
    }

    private func inspect(id: String) {
        Task { @MainActor in
        do {
            let text = try getLibrary().load(id: id)
            let host = try LXSourceScriptHost(script: text)
            activeHost = host
            message = "正在等待音源注册（最多 8 秒）…"
            let ready = await host.awaitRegistration(timeout: 8)
            let platforms = host.registeredSources.keys.sorted()
            let events = host.initializationEvents.suffix(8).joined(separator: "；")
            if ready {
                message = "初始化完成，已注册：\(platforms.joined(separator: ", "))。事件：\(events)"
            } else {
                message = "脚本加载完成，但 8 秒内未注册音源。收到 inited：\(host.didReceiveInitialization)；JS 错误：\(host.lastError ?? "无")；事件：\(events.isEmpty ? "无" : events)"
            }
            activeHost = nil
        } catch { message = "脚本检查失败：\(error.localizedDescription)"; activeHost = nil }
        }
    }

    @MainActor
    private func searchPlatform() async {
        isSearching = true
        defer { isSearching = false }
        selectedSong = nil
        searchResults = []
        stopPreview()
        previewURL = nil
        do {
            let query = [testSongName, testArtist].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: " ")
            let service = GDStudioMusicSearchService()
            let platform: MusicSource
            switch testPlatform {
            case "wy": platform = .netease
            case "kw": platform = .kuwo
            case "kg": platform = .kugou
            default: platform = .qq
            }
            let songs: [MusicSong]
            if testPlatform == "tx" {
                do {
                    songs = try await service.searchQQSongsNative(keyword: query, count: 20)
                } catch {
                    songs = try await service.search(keyword: query, source: platform, count: 20)
                }
            } else {
                songs = try await service.search(keyword: query, source: platform, count: 20)
            }
            searchResults = songs
            message = songs.isEmpty ? "当前平台未找到歌曲，请尝试只输入歌名。" : "找到 \(songs.count) 首歌曲，点击对应歌曲开始解析。"
        } catch {
            message = "歌曲搜索失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func resolveSelectedSong() async {
        guard let id = selectedID, let song = selectedSong else { return }
        isResolving = true
        previewPlayer?.pause()
        previewPlayer = nil
        previewURL = nil
        defer { isResolving = false; activeHost = nil }
        do {
            let script = try getLibrary().load(id: id)
            let host = try LXSourceScriptHost(script: script)
            activeHost = host
            let info: [String: Any] = [
                "songmid": song.sourceID,
                "id": song.sourceID,
                "name": song.title,
                "singer": song.artist,
                "albumName": song.album ?? "",
                "interval": Int(song.duration ?? 0),
                "hash": song.hash ?? song.sourceID
            ]
            let url = try await host.resolve(source: testPlatform, musicInfo: info, quality: "320k", timeout: 20)
            stopPreview()
            previewURL = url
            message = "解析成功，已取得 URL。点击试听验证播放：\(url.absoluteString)"
        } catch {
            message = "真实取链失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func stopPreview() {
        previewDiagnosticTask?.cancel()
        previewDiagnosticTask = nil
        previewPlayer?.pause()
        previewPlayer = nil
    }

    @MainActor
    private func togglePreview() {
        if previewPlayer != nil {
            stopPreview()
            message = "已停止试听。"
            return
        }
        guard let previewURL else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            message = "音频会话初始化失败：\(error.localizedDescription)"
            return
        }
        let item = AVPlayerItem(url: previewURL)
        let player = AVPlayer(playerItem: item)
        previewPlayer = player
        player.play()
        message = "已请求播放，正在检测音频加载状态…"
        previewDiagnosticTask = Task { @MainActor in
            for _ in 0..<12 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, previewPlayer === player else { return }
                if item.status == .failed {
                    message = "试听失败：\(item.error?.localizedDescription ?? "未知播放器错误")"
                    return
                }
                if player.timeControlStatus == .playing {
                    message = "播放器报告正在播放；请确认是否听到声音。"
                    return
                }
            }
            guard !Task.isCancelled else { return }
            let itemError = item.error?.localizedDescription ?? "无明确错误"
            message = "12 秒内未开始播放；itemStatus=\(item.status.rawValue)，timeControlStatus=\(player.timeControlStatus.rawValue)，reason=\(player.reasonForWaitingToPlay?.rawValue ?? "无")，error=\(itemError)"
        }
    }

    private func delete(at offsets: IndexSet) {
        do {
            let store = try getLibrary()
            for index in offsets { try store.remove(id: importedIDs[index]) }
            reload()
        } catch { message = "删除失败：\(error.localizedDescription)" }
    }
}
