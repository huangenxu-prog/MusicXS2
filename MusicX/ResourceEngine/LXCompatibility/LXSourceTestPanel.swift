import SwiftUI
import UniformTypeIdentifiers

/// Temporary test-only UI. Does not affect the normal music resource scheduler.
struct LXSourceTestPanel: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isImporterPresented = false
    @State private var importedIDs: [String] = []
    @State private var message: String?
    @State private var selectedID: String?
    @State private var library: LXSourceLibrary?

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
                if let message {
                    Section("测试结果") { Text(message).font(.footnote).textSelection(.enabled) }
                }
            }
            .navigationTitle("音源测试")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } } }
            .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.javascript, .plainText], allowsMultipleSelection: true) { result in
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

    private func delete(at offsets: IndexSet) {
        do {
            let store = try getLibrary()
            for index in offsets { try store.remove(id: importedIDs[index]) }
            reload()
        } catch { message = "删除失败：\(error.localizedDescription)" }
    }
}
