import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

private struct MXReferenceSourceDocument: FileDocument {
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

/// Warm-light source manager. Shares the real LXSourceLibrary and its cloud
/// location with the existing advanced panel. No extra source configuration.
struct MXReferenceSources: View {
    let onPreviewStart: () -> Void

    @Environment(\.dismiss) private var dismiss
    private struct SourceItem: Identifiable {
        let id: String
        let name: String
        let platforms: Set<String>
        let approved: Bool
        var isEnabled: Bool { approved && !platforms.isEmpty }
    }
    private struct TestHit: Identifiable {
        let platform: String
        let displayName: String
        let song: MusicSong?
        let error: String?
        var id: String { platform }
    }

    @State private var sourceItems: [SourceItem] = []
    @State private var isSourceListExpanded = false
    @State private var expandedSourceID: String?
    // The test target is an explicit JS script, never the playback fallback pool.
    @State private var testSourceID: String?
    @State private var testStatusByPlatform: [String: String] = [:]
    @State private var testedPlayingPlatform: String?
    @State private var activeTestHost: LXSourceScriptHost?
    @State private var previewCheckTask: Task<Void, Never>?
    @State private var message: String?
    @State private var isSyncing = false
    @State private var showJSImporter = false
    @State private var showBackupImporter = false
    @State private var showBackupExporter = false
    @State private var showURLImporter = false
    @State private var showAdvanced = false
    @State private var remoteURL = ""
    @State private var backupDocument: MXReferenceSourceDocument?

    @State private var testKeyword = ""
    @State private var isSearching = false
    @State private var testHits: [TestHit] = []
    @State private var previewPlayer: AVPlayer?
    @State private var previewPlatform: String?
    @State private var previewLoadingPlatform: String?
    @State private var previewRequestID = UUID()
    @State private var previewEndObserver: NSObjectProtocol?

    private let cloudURL =
        "https://raw.githubusercontent.com/huangenxu-prog/MusicXS2/test/build-486-complete-source/MusicX/CloudSources.json"

    private let platforms: [(id: String, title: String, source: MusicSource)] = [
        ("tx", "QQ 音乐", .qq), ("wy", "网易云", .netease),
        ("kw", "酷我音乐", .kuwo), ("kg", "酷狗音乐", .kugou)
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 40, height: 42, alignment: .leading)
                }
                Spacer()
                Text("音源管理")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Color.clear.frame(width: 40, height: 42)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(MXLight.ink)
            .font(.system(size: 19))
            .padding(.horizontal, 24)
            .padding(.top, 6)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("云端同步、音源导入与试听")
                        .font(.system(size: 13))
                        .foregroundStyle(MXLight.muted)
                        .padding(.bottom, 19)

                    HStack(spacing: 10) {
                        actionTile("云端同步", detail: "同步音源配置",
                                   symbol: "cloud", color: MXLight.ochre) {
                            Task { await syncCloud() }
                        }
                        Menu {
                            Button("从文件导入 JS", systemImage: "doc") {
                                showJSImporter = true
                            }
                            Button("从网址导入 JS", systemImage: "link") {
                                remoteURL = ""
                                showURLImporter = true
                            }
                        } label: {
                            tileLabel("导入音源", detail: "文件 / 链接",
                                      symbol: "square.and.arrow.down",
                                      color: MXLight.lightTeal)
                        }
                        Menu {
                            Button("导出音源配置", systemImage: "square.and.arrow.up",
                                   action: exportBackup)
                            Button("从本地备份恢复", systemImage: "square.and.arrow.down") {
                                showBackupImporter = true
                            }
                        } label: {
                            tileLabel("配置备份", detail: "导出 / 恢复",
                                      symbol: "square.stack", color: MXLight.cream)
                        }
                    }
                    if isSyncing {
                        ProgressView("正在同步音源")
                            .tint(MXLight.teal)
                            .padding(.top, 15)
                    }
                    if let message {
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundStyle(MXLight.muted)
                            .padding(.top, 14)
                    }

                    VStack(spacing: 0) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                isSourceListExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "music.note")
                                    .font(.system(size: 19))
                                    .foregroundStyle(.white)
                                    .frame(width: 43, height: 43)
                                    .background(MXLight.teal, in: RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("音源列表")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(MXLight.ink)
                                    Text("已启用 \(enabledCount) / \(sourceItems.count) 条音源")
                                        .font(.system(size: 12))
                                        .foregroundStyle(MXLight.muted)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: isSourceListExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(MXLight.ink)
                            }
                            .frame(minHeight: 63)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isSourceListExpanded ? "收起音源列表" : "展开音源列表")

                        if isSourceListExpanded {
                            MXLight.line.frame(height: 0.5)
                                .padding(.vertical, 7)
                            if sourceItems.isEmpty {
                                Text("暂无音源，先导入或从云端同步")
                                    .font(.system(size: 13))
                                    .foregroundStyle(MXLight.muted)
                                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                            } else {
                                ForEach(Array(sourceItems.enumerated()), id: \.element.id) { index, item in
                                    VStack(spacing: 0) {
                                        Button {
                                            withAnimation(.easeInOut(duration: 0.22)) {
                                                expandedSourceID = expandedSourceID == item.id ? nil : item.id
                                            }
                                        } label: {
                                            HStack(spacing: 10) {
                                                Image(systemName: "music.note")
                                                    .font(.system(size: 15))
                                                    .foregroundStyle(MXLight.teal)
                                                    .frame(width: 30, height: 30)
                                                    .background(MXLight.lightTeal, in: Circle())
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(item.name)
                                                        .font(.system(size: 14, weight: .medium))
                                                        .foregroundStyle(MXLight.ink)
                                                        .lineLimit(1)
                                                    Text(item.approved
                                                         ? "已启用 \(item.platforms.count) / 4 个平台"
                                                         : "待批准 · 已勾选 \(item.platforms.count) / 4")
                                                        .font(.system(size: 11))
                                                        .foregroundStyle(MXLight.muted)
                                                        .lineLimit(1)
                                                }
                                                Spacer(minLength: 6)
                                                Image(systemName: expandedSourceID == item.id
                                                      ? "chevron.up" : "chevron.down")
                                                    .font(.system(size: 15, weight: .semibold))
                                                    .foregroundStyle(MXLight.muted)
                                                    .frame(width: 32, height: 44)
                                            }
                                            .frame(minHeight: 58)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("\(item.name)，\(item.platforms.count) 个平台已勾选，点击展开设置")

                                        if expandedSourceID == item.id {
                                            VStack(spacing: 0) {
                                                MXLight.line.frame(height: 0.5)
                                                ForEach(Array(platforms.enumerated()), id: \.offset) { platformIndex, platform in
                                                    let checked = item.platforms.contains(platform.id)
                                                    Button {
                                                        togglePlatform(item, platform: platform.id)
                                                    } label: {
                                                        HStack(spacing: 12) {
                                                            Text(platform.title)
                                                                .font(.system(size: 14, weight: .medium))
                                                                .foregroundStyle(MXLight.ink)
                                                            Spacer()
                                                            Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                                                                .font(.system(size: 23))
                                                                .foregroundStyle(checked ? MXLight.teal : MXLight.muted)
                                                        }
                                                        .frame(minHeight: 46)
                                                        .contentShape(Rectangle())
                                                    }
                                                    .buttonStyle(.plain)
                                                    .accessibilityLabel("\(item.name) · \(platform.title) · \(checked ? "已勾选" : "未勾选")")
                                                    if platformIndex < platforms.count - 1 {
                                                        MXLight.line.frame(height: 0.5)
                                                    }
                                                }
                                                Button {
                                                    selectTestSource(item.id)
                                                } label: {
                                                    HStack(spacing: 6) {
                                                        Image(systemName: "waveform")
                                                        Text(testSourceID == item.id ? "当前测试音源" : "测试此音源")
                                                        Spacer()
                                                        Image(systemName: "chevron.right")
                                                    }
                                                    .font(.system(size: 13, weight: .semibold))
                                                    .foregroundStyle(testSourceID == item.id ? MXLight.teal : MXLight.red)
                                                    .frame(minHeight: 45)
                                                    .contentShape(Rectangle())
                                                }
                                                .buttonStyle(.plain)
                                                .accessibilityLabel("使用\(item.name)进行独立取链测试")
                                            }
                                            .padding(.leading, 40)
                                            .padding(.bottom, 8)
                                            .transition(.opacity.combined(with: .move(edge: .top)))
                                        }
                                    }
                                    if index < sourceItems.count - 1 {
                                        MXLight.line.frame(height: 0.5)
                                    }
                                }
                            }
                            Text("点击音源名称展开四个平台，再分别勾选；未通过试听批准的脚本不会参与正式播放。")
                                .font(.system(size: 11))
                                .foregroundStyle(MXLight.muted)
                                .padding(.top, 8)
                        }
                    }
                    .padding(16)
                    .background(MXLight.paper, in: RoundedRectangle(cornerRadius: 19))
                    .padding(.top, 22)

                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            Text("音源测试")
                                .font(.system(size: 19, weight: .bold))
                                .foregroundStyle(MXLight.ink)
                            Spacer()
                            Button {
                                showAdvanced = true
                            } label: {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 18))
                                    .foregroundStyle(MXLight.muted)
                                    .frame(width: 38, height: 38)
                            }
                            .accessibilityLabel("高级音源测试")
                        }
                        Menu {
                            ForEach(sourceItems) { item in
                                Button {
                                    selectTestSource(item.id)
                                } label: {
                                    Label(item.name, systemImage: testSourceID == item.id
                                          ? "checkmark.circle.fill" : "music.note")
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "square.stack.3d.up")
                                Text(testSourceID.flatMap { id in
                                    sourceItems.first(where: { $0.id == id })?.name
                                } ?? "请选择要测试的 JS 音源")
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.down")
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(testSourceID == nil ? MXLight.muted : MXLight.teal)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 46)
                            .background(MXLight.cream, in: RoundedRectangle(cornerRadius: 13))
                        }
                        .disabled(sourceItems.isEmpty)
                        .accessibilityLabel("选择独立测试音源")

                        HStack(spacing: 9) {
                            HStack(spacing: 9) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(MXLight.ink)
                                TextField("输入歌曲名", text: $testKeyword)
                                    .font(.system(size: 14))
                                    .foregroundStyle(MXLight.ink)
                                    .tint(MXLight.red)
                                    .autocorrectionDisabled()
                                    .submitLabel(.search)
                                    .onSubmit { Task { await searchFourPlatforms() } }
                                if !testKeyword.isEmpty {
                                    Button { testKeyword = "" } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(MXLight.muted)
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 45)
                            .background(MXLight.background, in: Capsule())

                            Button {
                                Task { await searchFourPlatforms() }
                            } label: {
                                if isSearching {
                                    ProgressView().tint(.white)
                                        .frame(width: 54, height: 45)
                                } else {
                                    Text("测试")
                                        .font(.system(size: 14, weight: .semibold))
                                        .frame(width: 54, height: 45)
                                }
                            }
                            .foregroundStyle(.white)
                            .background(MXLight.red, in: Capsule())
                            .disabled(isSearching || testSourceID == nil ||
                                      testKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        if testHits.isEmpty && !isSearching {
                            Text("先选定一条 JS 音源，再搜索歌曲。每个平台展示最多一首候选，试听只通过该 JS 音源取链。")
                                .font(.system(size: 12))
                                .foregroundStyle(MXLight.muted)
                                .padding(.vertical, 5)
                        } else {
                            Text(isSearching ? "正在搜索四个平台的歌曲信息…" : "点击歌曲，只测试所选 JS 音源对应平台")
                                .font(.system(size: 12))
                                .foregroundStyle(MXLight.muted)
                        }

                        ForEach(testHits) { hit in
                            if let song = hit.song {
                                Button {
                                    Task { await togglePreview(hit) }
                                } label: {
                                    HStack(spacing: 10) {
                                        MXLightArtwork(url: song.artworkURL,
                                                       size: 49,
                                                       variant: platforms.firstIndex(where: {
                                                           $0.id == hit.platform
                                                       }) ?? 0)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(song.title)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(MXLight.ink)
                                                .lineLimit(1)
                                            Text(song.artist)
                                                .font(.system(size: 12))
                                                .foregroundStyle(MXLight.muted)
                                                .lineLimit(1)
                                        }
                                        Spacer(minLength: 5)
                                        Text(hit.displayName)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(MXLight.teal)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 5)
                                            .background(MXLight.lightTeal, in: Capsule())
                                        Group {
                                            if previewLoadingPlatform == hit.platform {
                                                ProgressView().tint(MXLight.teal)
                                            } else {
                                                Image(systemName: previewPlatform == hit.platform
                                                      ? "stop.circle" : "play.circle")
                                                    .font(.system(size: 27))
                                                    .foregroundStyle(MXLight.teal)
                                            }
                                        }
                                        .frame(width: 32, height: 42)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("使用选定音源独立试听 \(hit.displayName) 的 \(song.title)")
                                if let status = testStatusByPlatform[hit.platform] {
                                    Text(status)
                                        .font(.system(size: 12))
                                        .foregroundStyle(MXLight.muted)
                                        .lineLimit(4)
                                }
                                if testedPlayingPlatform == hit.platform,
                                   let selectedID = testSourceID,
                                   let item = sourceItems.first(where: { $0.id == selectedID }),
                                   !item.approved {
                                    Button("确认听到声音 · 批准当前平台") {
                                        approveTestedPlatform(hit.platform)
                                    }
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(MXLight.teal)
                                    .frame(minHeight: 44, alignment: .leading)
                                }
                            } else {
                                HStack {
                                    Text(hit.displayName)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(MXLight.ink)
                                    Spacer()
                                    Text(hit.error == nil ? "暂无匹配" : "检索失败")
                                        .font(.system(size: 12))
                                        .foregroundStyle(MXLight.muted)
                                }
                                .frame(minHeight: 43)
                            }
                        }
                        Text("测试仅执行当前选中的 JS 脚本，不使用其他 JS、原生接口或缓存地址回退。搜索成功不等于取链成功；播放器开始播放后，还需确认实际有声。")
                            .font(.system(size: 11))
                            .foregroundStyle(MXLight.muted)
                    }
                    .padding(17)
                    .background(MXLight.paper, in: RoundedRectangle(cornerRadius: 19))
                    .padding(.top, 18)
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 30)
            }
        }
        .background(MXLight.background.ignoresSafeArea())
        .preferredColorScheme(.light)
        .onAppear(perform: reload)
        .onDisappear(perform: stopPreview)
        .sheet(isPresented: $showAdvanced, onDismiss: reload) {
            LXSourceTestPanel().preferredColorScheme(.dark)
        }
        .fileImporter(isPresented: $showJSImporter,
                      allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            do {
                let files = try result.get()
                let lib = try LXSourceLibrary()
                var count = 0
                for file in files {
                    _ = try lib.importScript(from: file)
                    count += 1
                }
                message = "已导入 \(count) 条音源，试听通过后才能启用。"
                reload()
            } catch {
                message = "音源导入失败：\(error.localizedDescription)"
            }
        }
        .fileImporter(isPresented: $showBackupImporter,
                      allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            do {
                guard let file = try result.get().first else { return }
                let granted = file.startAccessingSecurityScopedResource()
                defer { if granted { file.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: file)
                let count = try LXSourceLibrary().restoreSourceArchive(data)
                message = "从备份恢复了 \(count) 条音源。"
                reload()
            } catch {
                message = "音源备份恢复失败：\(error.localizedDescription)"
            }
        }
        .fileExporter(isPresented: $showBackupExporter,
                      document: backupDocument, contentType: .json,
                      defaultFilename: "MusicXS2-LXSource-Backup") { result in
            if case .failure(let error) = result {
                message = "音源备份导出失败：\(error.localizedDescription)"
            }
            backupDocument = nil
        }
        .alert("从网址导入 JS 音源", isPresented: $showURLImporter) {
            TextField("https://…/source.js", text: $remoteURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("取消", role: .cancel) {}
            Button("导入") { Task { await importFromURL() } }
        } message: {
            Text("仅接受 HTTPS JS 直链，导入后仍需试听验证。")
        }
    }

    private var enabledCount: Int { sourceItems.filter(\.isEnabled).count }

    private func tileLabel(_ title: String, detail: String, symbol: String, color: Color) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(MXLight.teal)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MXLight.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(MXLight.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 104)
        .background(color, in: RoundedRectangle(cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }

    private func actionTile(_ title: String, detail: String, symbol: String,
                            color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            tileLabel(title, detail: detail, symbol: symbol, color: color)
        }
        .buttonStyle(.plain)
    }

    @MainActor private func reload() {
        do {
            let lib = try LXSourceLibrary()
            sourceItems = try lib.listIdentifiers().map { id in
                SourceItem(id: id, name: (try? lib.filename(id: id)) ?? id,
                           platforms: lib.enabledPlatforms(id: id),
                           approved: lib.isBundled(id: id) ||
                                     lib.approvedIDs.contains(id.lowercased()))
            }
        } catch {
            message = "无法读取本地音源：\(error.localizedDescription)"
        }
    }

    @MainActor private func togglePlatform(_ item: SourceItem, platform: String) {
        guard LXSourceLibrary.playbackPlatforms.contains(platform) else { return }
        do {
            let lib = try LXSourceLibrary()
            let wasEnabled = lib.enabledPlatforms(id: item.id).contains(platform)
            try lib.setPlatformEnabled(id: item.id, platform: platform, enabled: !wasEnabled)
            reload()
            if !item.approved && !wasEnabled {
                message = "已保存平台勾选，但音源仍需在高级测试中通过试听才能参与播放。"
            } else {
                message = nil
            }
        } catch {
            message = "更改平台状态失败：\(error.localizedDescription)"
        }
    }

    private func displayPlatforms(_ platforms: Set<String>) -> String {
        if platforms.isEmpty { return "已停用" }
        let names = ["tx": "QQ", "wy": "网易云", "kw": "酷我", "kg": "酷狗"]
        return platforms.sorted().map { names[$0] ?? $0 }.joined(separator: " · ")
    }

    @MainActor private func searchFourPlatforms() async {
        let keyword = testKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty && !isSearching,
              let selectedSource = testSourceID,
              sourceItems.contains(where: { $0.id == selectedSource }) else {
            message = "请先选定一条 JS 音源，再输入歌曲名测试"
            return
        }
        stopPreview()
        testStatusByPlatform = [:]
        isSearching = true
        testHits = []
        defer { isSearching = false }

        var hits: [String: TestHit] = [:]
        await withTaskGroup(of: (String, MusicSong?, String?).self) { group in
            for (platform, _, _) in platforms {
                group.addTask {
                    let svc = GDStudioMusicSearchService()
                    do {
                        let songs: [MusicSong]
                        switch platform {
                        case "tx":
                            songs = try await svc.searchQQSongsNative(keyword: keyword, count: 6)
                        case "wy":
                            songs = try await svc.search(keyword: keyword, source: .netease, count: 6)
                        case "kw":
                            songs = try await svc.searchKuwoNative(keyword: keyword, count: 6)
                        default:
                            songs = try await svc.searchKugouNative(keyword: keyword, count: 6)
                        }
                        let exact = songs.first(where: {
                            $0.title.localizedCaseInsensitiveContains(keyword)
                        })
                        return (platform, exact ?? songs.first, nil)
                    } catch {
                        return (platform, nil, error.localizedDescription)
                    }
                }
            }
            for await (platform, song, error) in group {
                let name = platforms.first(where: { $0.id == platform })?.title ?? platform
                hits[platform] = TestHit(platform: platform, displayName: name,
                                         song: song, error: error)
            }
        }
        guard !Task.isCancelled, testSourceID == selectedSource else { return }
        testHits = platforms.map {
            hits[$0.id] ?? TestHit(platform: $0.id, displayName: $0.title,
                                  song: nil, error: nil)
        }
    }

    @MainActor private func selectTestSource(_ id: String) {
        guard sourceItems.contains(where: { $0.id == id }) else { return }
        stopPreview()
        testSourceID = id
        testHits = []
        testStatusByPlatform = [:]
        message = nil
    }

    /// The only resolver used by this test is the user's chosen LX JS script.
    /// Never use LXMusicURLResolver, MusicResourceEngine or cross-provider fallback.
    @MainActor private func togglePreview(_ result: TestHit) async {
        guard let song = result.song, let id = testSourceID else {
            message = "请先选择一条要测试的 JS 音源"
            return
        }
        guard previewLoadingPlatform == nil else { return }
        if previewPlatform == result.platform {
            stopPreview()
            testStatusByPlatform[result.platform] = "已停止试听"
            return
        }

        stopPreview()
        let request = UUID()
        previewRequestID = request
        let platform = result.platform
        previewLoadingPlatform = platform
        testStatusByPlatform[platform] = "正在初始化所选 JS 音源…"
        message = nil

        do {
            let library = try LXSourceLibrary()
            let script = try library.load(id: id)
            let host = try LXSourceScriptHost(script: script)
            activeTestHost = host
            let ready = await host.awaitRegistration(timeout: 8)
            guard request == previewRequestID, testSourceID == id,
                  !Task.isCancelled else { return }
            guard ready else {
                throw LXSourceScriptHost.HostError.initialization(
                    "脚本没有成功注册：\(host.lastError ?? "注册超时或没有提供任何平台")")
            }
            guard let sourceMeta = host.registeredSources[platform] as? [String: Any] else {
                let registered = host.registeredSources.keys.sorted().joined(separator: "、")
                testStatusByPlatform[platform] =
                    "不支持当前平台（脚本注册：\(registered.isEmpty ? "无" : registered)）"
                previewLoadingPlatform = nil
                activeTestHost = nil
                return
            }

            let qualities = sourceMeta["qualitys"] as? [String] ?? []
            let quality = qualities.contains("320k") || qualities.isEmpty
                ? "320k" : (qualities.contains("128k") ? "128k" : qualities[0])
            let musicInfo: [String: Any] = [
                "songmid": song.sourceID,
                "id": song.sourceID,
                "name": song.title,
                "singer": song.artist,
                "albumName": song.album ?? "",
                "interval": Int(song.duration ?? 0),
                "hash": song.hash ?? song.sourceID,
                "albumId": song.albumID ?? ""
            ]
            testStatusByPlatform[platform] = "正在通过这条 JS 音源解析 \(quality)…"
            let url = try await host.resolve(source: platform, musicInfo: musicInfo,
                                             quality: quality, timeout: 20)
            guard request == previewRequestID, testSourceID == id,
                  !Task.isCancelled else { return }

            // A returned URL alone is not a successful test.
            testStatusByPlatform[platform] = "取得候选地址，正在验证 AVPlayer 播放…"
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            onPreviewStart() // Pause the normal queue so two players cannot overlap.
            let item = AVPlayerItem(url: url)
            let player = AVPlayer(playerItem: item)
            previewPlayer = player
            previewPlatform = platform
            previewLoadingPlatform = nil
            previewEndObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
            ) { _ in
                Task { @MainActor in
                    guard previewRequestID == request else { return }
                    stopPreview()
                    testStatusByPlatform[platform] = "试听结束"
                }
            }
            player.play()
            previewCheckTask = Task { @MainActor in
                for _ in 0..<12 {
                    do { try await Task.sleep(for: .seconds(1)) }
                    catch { return }
                    guard !Task.isCancelled, previewRequestID == request,
                          previewPlayer === player, testSourceID == id else { return }
                    if item.status == .failed {
                        testStatusByPlatform[platform] =
                            "播放失败：\(item.error?.localizedDescription ?? "AVPlayer 无法加载此地址")"
                        stopPreview()
                        return
                    }
                    let position = player.currentTime().seconds
                    if player.timeControlStatus == .playing,
                       position.isFinite && position > 0.35 {
                        // System state proves playback progress, not audible output.
                        testStatusByPlatform[platform] =
                            "播放器已启动且进度正常；请确认能听到声音"
                        testedPlayingPlatform = platform
                        return
                    }
                }
                guard !Task.isCancelled, previewRequestID == request else { return }
                testStatusByPlatform[platform] = "播放失败：12 秒内未开始播放"
                stopPreview()
            }
        } catch {
            guard previewRequestID == request else { return }
            testStatusByPlatform[platform] = "此 JS 音源取链或试听失败：\(error.localizedDescription)"
            stopPreview()
        }
    }

    @MainActor private func approveTestedPlatform(_ platform: String) {
        guard testedPlayingPlatform == platform, let id = testSourceID,
              previewPlatform == platform else { return }
        do {
            let library = try LXSourceLibrary()
            try library.approve(id: id, testedPlatform: platform)
            try library.setPlatformEnabled(id: id, platform: platform, enabled: true)
            reload()
            testStatusByPlatform[platform] = "已确认试听并批准此平台"
            message = "已批准所选 JS 音源的 \(platforms.first(where: { $0.id == platform })?.title ?? platform) 通道"
        } catch {
            message = "批准失败：\(error.localizedDescription)"
        }
    }

    @MainActor private func stopPreview() {
        previewRequestID = UUID()
        previewCheckTask?.cancel()
        previewCheckTask = nil
        previewPlayer?.pause()
        previewPlayer = nil
        previewPlatform = nil
        previewLoadingPlatform = nil
        testedPlayingPlatform = nil
        activeTestHost = nil
        if let observer = previewEndObserver {
            NotificationCenter.default.removeObserver(observer)
            previewEndObserver = nil
        }
    }

    @MainActor private func syncCloud() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            guard let url = URL(string: cloudURL) else { return }
            let request = URLRequest(url: url,
                                     cachePolicy: .reloadIgnoringLocalCacheData,
                                     timeoutInterval: 30)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200 else { throw URLError(.badServerResponse) }
            let count = try LXSourceLibrary().restoreSourceArchive(
                data, replaceImported: true)
            reload()
            message = "已同步 \(count) 条音源及平台启用状态。"
        } catch {
            message = "云端同步失败：\(error.localizedDescription)"
        }
    }

    @MainActor private func importFromURL() async {
        do {
            let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: trimmed), url.scheme?.lowercased() == "https",
                  url.host != nil, url.user == nil, url.password == nil else {
                message = "请输入有效的 HTTPS JS 直链"
                return
            }
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let name = url.lastPathComponent.lowercased().hasSuffix(".js")
                       ? url.lastPathComponent : "online-source.js"
            let script = try LXSourceLibrary().importScript(data: data, filename: name)
            reload()
            message = "已导入 \(script.filename)，请先进入高级测试试听。"
        } catch {
            message = "在线音源导入失败：\(error.localizedDescription)"
        }
    }

    @MainActor private func exportBackup() {
        do {
            backupDocument = MXReferenceSourceDocument(
                contents: try LXSourceLibrary().exportSourceArchive())
            showBackupExporter = true
        } catch {
            message = "生成备份失败：\(error.localizedDescription)"
        }
    }
}
