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
    @State private var testSongMID = ""
    @State private var testSongName = ""
    @State private var testArtist = ""
    @State private var isResolving = false
    @State private var activeHost: LXSourceScriptHost?
    @State private var previewPlayer: AVPlayer?
    @State private var previewURL: URL?

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
                Section("QQ 真实取链测试") {
                    TextField("QQ songmid（必填）", text: $testSongMID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("歌曲名称（可选）", text: $testSongName)
                    TextField("歌手名称（可选）", text: $testArtist)
                    Button(isResolving ? "正在解析…" : "用当前音源测试 QQ 取链") {
                        Task { await resolveSelectedQQ() }
                    }
                    .disabled(isResolving || selectedID == nil || testSongMID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if previewURL != nil {
                        Button(previewPlayer == nil ? "试听解析结果" : "停止试听") { togglePreview() }
                    }
                    Text("先解析 URL，再手动试听。部分音源可能要求授权或返回地区限制。")
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
            .onDisappear { previewPlayer?.pause(); previewPlayer = nil }
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
        do {
            let text = try getLibrary().load(id: id)
            let host = try LXSourceScriptHost(script: text)
            let platforms = host.registeredSources.keys.sorted()
            message = platforms.isEmpty ? "脚本已加载，但未注册音源。" : "初始化完成，已注册：\(platforms.joined(separator: ", "))。未进行真实取链测试。"
        } catch { message = "脚本检查失败：\(error.localizedDescription)" }
    }

    @MainActor
    private func resolveSelectedQQ() async {
        guard let id = selectedID else { return }
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
                "songmid": testSongMID.trimmingCharacters(in: .whitespacesAndNewlines),
                "name": testSongName,
                "singer": testArtist
            ]
            let url = try await host.resolve(source: "tx", musicInfo: info, quality: "320k", timeout: 20)
            previewPlayer?.pause()
            previewPlayer = nil
            previewURL = url
            message = "解析成功，已取得 URL。点击试听验证播放：\(url.absoluteString)"
        } catch {
            message = "真实取链失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func togglePreview() {
        if let previewPlayer {
            previewPlayer.pause()
            self.previewPlayer = nil
            message = "已停止试听。"
            return
        }
        guard let previewURL else { return }
        let player = AVPlayer(url: previewURL)
        previewPlayer = player
        player.play()
        message = "已发起试听，请确认是否听到声音。无声音不能视为验证通过。"
    }

    private func delete(at offsets: IndexSet) {
        do {
            let store = try getLibrary()
            for index in offsets { try store.remove(id: importedIDs[index]) }
            reload()
        } catch { message = "删除失败：\(error.localizedDescription)" }
    }
}
