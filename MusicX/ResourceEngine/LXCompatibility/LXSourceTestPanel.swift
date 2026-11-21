import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

private struct LXSourceBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }
    var contents: Data

    init(contents: Data) { self.contents = contents }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        contents = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: contents)
    }
}

/// Temporary test-only UI. Does not affect the normal music resource scheduler.
struct LXSourceTestPanel: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isImporterPresented = false
    @State private var isSourceBackupExporterPresented = false
    @State private var isSourceBackupImporterPresented = false
    @State private var sourceBackupDocument: LXSourceBackupDocument?
    @State private var isURLImporterPresented = false
    @State private var remoteScriptURL = ""
    @State private var isSyncingSources = false
    @State private var isImportingRemote = false
    @State private var importedIDs: [String] = []
    @State private var expandedID: String?
    @State private var platformSelections: [String: Set<String>] = [:]
    @State private var message: String?
    @State private var selectedID: String?
    @State private var library: LXSourceLibrary?
    @State private var searchResults: [String: [MusicSong]] = [:]
    @State private var searchErrors: [String: String] = [:]
    @State private var selectedSong: MusicSong?
    @State private var isSearching = false
    @State private var testSongName = ""
    @State private var testArtist = ""
    @State private var isResolving = false
    @State private var activeHost: LXSourceScriptHost?
    @State private var previewPlayer: AVPlayer?
    @State private var previewURL: URL?
    @State private var previewDiagnosticTask: Task<Void, Never>?
    @State private var isProbingURL = false

    var body: some View {
        NavigationStack {
            List {
                Section("测试音源") {
                    if importedIDs.isEmpty {
                        Text("尚未导入 JS 音源").foregroundStyle(.secondary)
                    }
                    ForEach(importedIDs, id: \.self) { id in
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                Button {
                                    if expandedID == id {
                                        expandedID = nil
                                    } else {
                                        expandedID = id
                                        do {
                                            try getLibrary().select(id: id)
                                            selectedID = id
                                            message = "正在设置音源的四个平台。勾选即加入正式播放，取消勾选即跳过。"
                                        } catch { message = error.localizedDescription }
                                    }
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: expandedID == id ? "chevron.down" : "chevron.right")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text((try? getLibrary().filename(id: id)) ?? id)
                                                .lineLimit(1)
                                            Text("已启用 \(platformSelections[id]?.count ?? 0) / 4 个平台")
                                                .font(.caption2).foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 4)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Spacer(minLength: 4)
                                Button("检查") { inspect(id: id) }
                                    .buttonStyle(.bordered)
                            }
                            if expandedID == id {
                                ForEach(["tx", "wy", "kw", "kg"], id: \.self) { platform in
                                    Toggle(isOn: Binding(
                                        get: { platformSelections[id]?.contains(platform) == true },
                                        set: { setPlatform(id: id, platform: platform, enabled: $0) }
                                    )) {
                                        HStack(spacing: 6) {
                                            Text(platformDisplayName(platform))
                                        }
                                    }
                                }
                                Text("仅控制这条音源的正式播放通道；新导入音源需先试听通过，勾选才会生效。")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: delete)
                }
                Section {
                    Text("点击音源名称展开四个平台，勾选启用、取消勾选停用；展开后也会将该音源设为当前测试对象。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("备份音源与启用设置") { exportSourceBackup() }
                    Button("从备份恢复音源与设置") { isSourceBackupImporterPresented = true }
                    Button(isSyncingSources ? "正在同步音源…" : "云端同步音源") {
                        Task { await syncCloudSources() }
                    }
                    .disabled(isSyncingSources)
                    Text("备份包含导入的 JS 源码及平台勾选状态，请妥善保存；恢复不会删除现有音源。")
                        .font(.caption2).foregroundStyle(.secondary)
                    Button("从文件导入 .js 音源") { isImporterPresented = true }
                    Button("从网址导入在线 JS 音源") {
                        // Do not reuse the last URL when opening a new import dialog.
                        remoteScriptURL = ""
                        isURLImporterPresented = true
                    }
                }
                Section("多平台歌曲搜索与试听") {
                    TextField("歌曲名称", text: $testSongName)
                    TextField("歌手名称（可选）", text: $testArtist)
                    Button(isSearching ? "四个平台搜索中…" : "搜索四个平台") {
                        Task { await searchPlatform() }
                    }
                    .disabled(isSearching || testSongName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    ForEach(["tx", "wy", "kw", "kg"], id: \.self) { platform in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(platformDisplayName(platform))
                                    .font(.headline)
                                Spacer()
                                if isSearching && searchResults[platform] == nil && searchErrors[platform] == nil {
                                    ProgressView().controlSize(.small)
                                }
                            }
                            if let error = searchErrors[platform] {
                                Text("搜索失败：\(error)")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else if let songs = searchResults[platform] {
                                if songs.isEmpty {
                                    Text("没有找到歌曲")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                ForEach(songs) { song in
                                    Button {
                                        selectedSong = song
                                        Task { await resolveSelectedSong() }
                                    } label: {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(song.title)
                                            Text(song.artist).font(.caption).foregroundStyle(.secondary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .disabled(isResolving || selectedID == nil || isProbingURL)
                                }
                            }
                        }
                    }
                    if isResolving { ProgressView("正在解析选中的歌曲…") }
                    if previewURL != nil {
                        Button(previewPlayer == nil ? "试听解析结果" : "停止试听") { togglePreview() }
                        .disabled(isProbingURL)
                        Text(isProbingURL ? "正在自动验证地址是否返回真实音频…" : "HTTP 检查自动执行；是否实际出声以最终试听为准。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("一次搜索 QQ、网易云、酷我、酷狗，每个平台最多显示 5 首；点击歌曲测试当前音源对应平台。")
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
            .fileExporter(
                isPresented: $isSourceBackupExporterPresented,
                document: sourceBackupDocument,
                contentType: .json,
                defaultFilename: "MusicXS2-LXSource-Backup"
            ) { result in
                if case .failure(let error) = result {
                    message = "音源备份导出失败：\(error.localizedDescription)"
                } else {
                    message = "音源备份已导出，请妥善保存 JSON 文件。"
                }
                sourceBackupDocument = nil
            }
            .fileImporter(
                isPresented: $isSourceBackupImporterPresented,
                allowedContentTypes: [.json]
            ) { result in
                do {
                    let url = try result.get()
                    let granted = url.startAccessingSecurityScopedResource()
                    defer { if granted { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    try restoreSourceData(data)
                } catch {
                    message = "音源备份恢复失败：\(error.localizedDescription)"
                }
            }
            .alert("在线音源导入", isPresented: $isURLImporterPresented) {
                TextField("https://…/source.js", text: $remoteScriptURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("取消", role: .cancel) {}
                Button("导入") { Task { await importRemoteScript() } }
            } message: {
                Text("输入 HTTPS 的 JS 文件直链。导入后自动检查注册；解析歌曲时自动检查播放地址。")
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

    @MainActor
    private func syncCloudSources() async {
        guard !isSyncingSources else { return }
        isSyncingSources = true
        defer { isSyncingSources = false }
        do {
            let url = URL(string: "https://raw.githubusercontent.com/huangenxu-prog/MusicXS2/test/build-486-complete-source/MusicX/CloudSources.json")!
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let library = try getLibrary()
            let count = try library.restoreSourceArchive(data, replaceImported: true)
            reload()
            message = "已同步 \(count) 个导入音源，并更新内置音源的平台勾选。"
        } catch {
            message = "云端同步失败：\(error.localizedDescription)"
        }
    }

    private func restoreSourceData(_ data: Data) throws {
        let count = try getLibrary().restoreSourceArchive(data)
        reload()
        message = "已从备份恢复 \(count) 条导入音源及各平台勾选设置；未删除原有其他音源。"
    }

    private func exportSourceBackup() {
        do {
            sourceBackupDocument = LXSourceBackupDocument(contents: try getLibrary().exportSourceArchive())
            isSourceBackupExporterPresented = true
        } catch {
            message = "创建音源备份失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func setPlatform(id: String, platform: String, enabled: Bool) {
        do {
            try getLibrary().setPlatformEnabled(id: id, platform: platform, enabled: enabled)
            platformSelections[id] = getLibrarySafePlatforms(id: id)
            let approved = (try? getLibrary().isBundled(id: id)) == true || ((try? getLibrary().approvedIDs.contains(id)) == true)
            message = approved ? "\(platformDisplayName(platform))已\(enabled ? "启用" : "停用")，下次正式取链时生效。" : "已保存勾选设置；需要先试听成功，才会参与正式播放。"
        } catch {
            message = "无法修改平台：\(error.localizedDescription)"
        }
    }

    private func getLibrarySafePlatforms(id: String) -> Set<String> {
        (try? getLibrary().enabledPlatforms(id: id)) ?? []
    }

    private func reload() {
        do {
            let store = try getLibrary()
            importedIDs = try store.listIdentifiers()
            platformSelections = Dictionary(uniqueKeysWithValues: importedIDs.map { ($0, store.enabledPlatforms(id: $0)) })
            if let expandedID, !importedIDs.contains(expandedID) { self.expandedID = nil }
            selectedID = store.selectedID.flatMap { importedIDs.contains($0) ? $0 : nil } ?? importedIDs.first
            if let selectedID, store.selectedID != selectedID { try store.select(id: selectedID) }
        }
        catch { message = "读取失败：\(error.localizedDescription)" }
    }

    @MainActor
    private func importRemoteScript() async {
        guard !isImportingRemote else { return }
        isImportingRemote = true
        defer { isImportingRemote = false }
        let input = remoteScriptURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: input), url.scheme?.lowercased() == "https",
              url.host != nil, url.user == nil, url.password == nil else {
            message = "导入失败：请输入有效的 HTTPS JS 直链"
            return
        }
        message = "正在获取在线音源…"
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.setValue("application/javascript, text/javascript, text/plain", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                message = "在线音源下载失败：HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"
                return
            }
            guard data.count <= 2 * 1024 * 1024 else {
                message = "导入失败：JS 文件超过 2 MB"
                return
            }
            // Some online sources use a versioned or extensionless download URL.
            // Store them as .js while keeping the source's original filename where possible.
            let rawName = http.url?.lastPathComponent ?? url.lastPathComponent
            let filename = rawName.lowercased().hasSuffix(".js") ? rawName : "online-source.js"
            let imported = try getLibrary().importScript(data: data, filename: filename)
            reload()
            try getLibrary().select(id: imported.id)
            selectedID = imported.id
            remoteScriptURL = ""
            inspect(id: imported.id)
            message = "在线音源已导入：\(imported.filename)。正在自动检查注册。"
        } catch {
            message = "在线音源导入失败：\(error.localizedDescription)"
        }
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
                let detail = platforms.map { platform -> String in
                    let metadata = host.registeredSources[platform] as? [String: Any]
                    let qualities = metadata?["qualitys"] as? [String] ?? []
                    return "\(platform)[\(qualities.joined(separator: ", "))]"
                }.joined(separator: "；")
                message = "初始化完成，平台及音质：\(detail)。事件：\(events)"
            } else {
                message = "脚本加载完成，但 8 秒内未注册音源。收到 inited：\(host.didReceiveInitialization)；JS 错误：\(host.lastError ?? "无")；事件：\(events.isEmpty ? "无" : events)"
            }
            activeHost = nil
        } catch { message = "脚本检查失败：\(error.localizedDescription)"; activeHost = nil }
        }
    }

    private func platformDisplayName(_ platform: String) -> String {
        switch platform {
        case "tx": return "QQ 音乐"
        case "wy": return "网易云音乐"
        case "kw": return "酷我音乐"
        case "kg": return "酷狗音乐"
        default: return platform
        }
    }

    private func platformID(for source: MusicSource) -> String {
        switch source {
        case .qq: return "tx"
        case .netease: return "wy"
        case .kuwo: return "kw"
        case .kugou: return "kg"
        default: return ""
        }
    }

    @MainActor
    private func searchPlatform() async {
        guard !isSearching else { return }
        isSearching = true
        defer { isSearching = false }
        selectedSong = nil
        searchResults = [:]
        searchErrors = [:]
        stopPreview()
        previewURL = nil
        let query = [testSongName, testArtist]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")
        message = "四个平台并发搜索中，每个平台最多返回 5 首歌曲…"
        await withTaskGroup(of: (String, [MusicSong], String?).self) { group in
            for platform in ["tx", "wy", "kw", "kg"] {
                group.addTask {
                    let service = GDStudioMusicSearchService()
                    do {
                        let songs: [MusicSong]
                        switch platform {
                        case "tx":
                            songs = try await service.searchQQSongsNative(keyword: query, count: 5)
                        case "kw":
                            songs = try await service.searchKuwoNative(keyword: query, count: 5)
                        case "kg":
                            songs = try await service.searchKugouNative(keyword: query, count: 5)
                        default:
                            songs = try await service.search(keyword: query, source: .netease, count: 5)
                        }
                        return (platform, Array(songs.prefix(5)), nil)
                    } catch {
                        return (platform, [], error.localizedDescription)
                    }
                }
            }
            for await (platform, songs, error) in group {
                if let error {
                    searchErrors[platform] = error
                } else {
                    searchResults[platform] = songs
                }
            }
        }
        let total = searchResults.values.reduce(0) { $0 + $1.count }
        message = "四个平台搜索完成：共 \(total) 首候选歌曲；每个平台最多 5 首。点选任意歌曲即可测试对应平台。"
    }

    @MainActor
    private func resolveSelectedSong() async {
        guard !isResolving, let id = selectedID, let song = selectedSong else { return }
        let selectedPlatform = platformID(for: song.source)
        guard !selectedPlatform.isEmpty else { return }
        isResolving = true
        previewPlayer?.pause()
        previewPlayer = nil
        previewURL = nil
        defer { isResolving = false; activeHost = nil }
        do {
            let script = try getLibrary().load(id: id)
            let host = try LXSourceScriptHost(script: script)
            activeHost = host
            // Some community sources register only after an asynchronous update
            // check. Never resolve until the source has announced "inited".
            let registered = await host.awaitRegistration(timeout: 8)
            guard registered, host.registeredSources[selectedPlatform] != nil else {
                let events = host.initializationEvents.suffix(8).joined(separator: "；")
                let platforms = host.registeredSources.keys.sorted().joined(separator: ", ")
                throw LXSourceScriptHost.HostError.initialization(
                    "音源未注册当前平台 \(selectedPlatform)；已注册：\(platforms.isEmpty ? "无" : platforms)；JS 错误：\(host.lastError ?? "无")；事件：\(events.isEmpty ? "无" : events)"
                )
            }
            let info: [String: Any] = [
                "songmid": song.sourceID,
                "id": song.sourceID,
                "name": song.title,
                "singer": song.artist,
                "albumName": song.album ?? "",
                "interval": Int(song.duration ?? 0),
                "hash": song.hash ?? song.sourceID,
                "albumId": song.albumID ?? ""
            ]
            // LX sources advertise their supported qualities per platform.
            // Do not force 320k when a script only registers 128k (e.g. fallback sources).
            let sourceMetadata = host.registeredSources[selectedPlatform] as? [String: Any]
            let supportedQualities = sourceMetadata?["qualitys"] as? [String] ?? []
            let quality = supportedQualities.isEmpty || supportedQualities.contains("320k")
                ? "320k" : (supportedQualities.contains("128k") ? "128k" : supportedQualities[0])
            let url = try await host.resolve(source: selectedPlatform, musicInfo: info, quality: quality, timeout: 20)
            stopPreview()
            previewURL = url
            message = "取得候选播放地址，正在自动检查 HTTP 响应和音频特征…"
            let report = await probePreviewURL(url)
            // Ignore a stale probe if a later search or platform switch replaced the URL.
            if previewURL == url {
                message = "取链音质：\(quality)。\(report)；地址：\(url.absoluteString)"
            }
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

    /// Inspect a small streaming prefix, never download the whole track.
    /// This is a technical HTTP check, not proof that AVPlayer emits sound.
    @MainActor
    private func probePreviewURL(_ url: URL) async -> String {
        isProbingURL = true
        defer { isProbingURL = false }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("bytes=0-255", forHTTPHeaderField: "Range")
        request.timeoutInterval = 12
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse else {
                return "HTTP 检查失败：服务器未返回 HTTP 响应"
            }
            let mime = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            let domain = http.url?.host ?? "未知"
            guard (200...299).contains(http.statusCode) else {
                return "HTTP 检查失败：状态码 \(http.statusCode)，域名 \(domain)"
            }
            var prefix = [UInt8]()
            for try await byte in bytes {
                prefix.append(byte)
                if prefix.count >= 128 { break }
            }
            guard !prefix.isEmpty else {
                return "HTTP 检查失败：返回了空数据（\(domain)）"
            }
            let rawText = String(bytes: prefix, encoding: .utf8)?.lowercased() ?? ""
            let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            let isPage = trimmed.hasPrefix("{") || trimmed.hasPrefix("[") ||
                trimmed.hasPrefix("<") || rawText.contains("<html") || rawText.contains("<!doctype")
            if isPage || mime.contains("application/json") || mime.contains("text/html") {
                return "HTTP 检查失败：服务器返回网页或 JSON，而不是音频（\(domain)）"
            }
            let isID3 = prefix.starts(with: [0x49, 0x44, 0x33])
            let isMP3 = prefix.count >= 2 && prefix[0] == 0xFF && (prefix[1] & 0xE0) == 0xE0
            let isFLAC = prefix.starts(with: [0x66, 0x4C, 0x61, 0x43])
            let isOgg = prefix.starts(with: [0x4F, 0x67, 0x67, 0x53])
            let isMp4 = prefix.count >= 8 && Array(prefix[4..<8]) == [0x66, 0x74, 0x79, 0x70]
            if isID3 || isMP3 || isFLAC || isOgg || isMp4 {
                return "HTTP 检查通过：\(http.statusCode)，检测到音频文件特征（\(domain)）；尚未确认出声"
            }
            if mime.contains("audio/") || mime.contains("application/octet-stream") {
                return "HTTP 检查初步通过：\(http.statusCode)，音频 MIME=\(mime)（\(domain)），文件头未识别；尚未确认出声"
            }
            return "HTTP \(http.statusCode)；文件头和 MIME 未能确认音频（\(domain)），需要进一步验证"
        } catch {
            return "HTTP 检查未通过：\(error.localizedDescription)"
        }
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
                    message = "试听失败（AVPlayer）：\(item.error?.localizedDescription ?? "未知播放器错误")；地址域名：\(previewURL.host ?? "未知")。解析成功不代表地址可播放。"
                    return
                }
                if player.timeControlStatus == .playing {
                    if let id = selectedID {
                        do {
                            try getLibrary().approve(
                                id: id,
                                testedPlatform: selectedSong.map { platformID(for: $0.source) }
                            )
                            reload()
                            message = "播放器报告正在播放；试听平台已加入正式播放通道。请确认是否听到声音。"
                        } catch {
                            message = "播放器正在播放，但启用音源失败：\(error.localizedDescription)"
                        }
                    } else {
                        message = "播放器报告正在播放；请确认是否听到声音。"
                    }
                    return
                }
            }
            guard !Task.isCancelled else { return }
            let itemError = item.error?.localizedDescription ?? "无明确错误"
            message = "12 秒内未开始播放；域名=\(previewURL.host ?? "未知")，itemStatus=\(item.status.rawValue)，timeControlStatus=\(player.timeControlStatus.rawValue)，reason=\(player.reasonForWaitingToPlay?.rawValue ?? "无")，error=\(itemError)"
        }
    }

    private func delete(at offsets: IndexSet) {
        do {
            let store = try getLibrary()
            for index in offsets {
                let id = importedIDs[index]
                if store.isBundled(id: id) {
                    message = "内置音源无法删除，可直接测试或切换。"
                    continue
                }
                try store.remove(id: id)
            }
            reload()
        } catch { message = "删除失败：\(error.localizedDescription)" }
    }
}
