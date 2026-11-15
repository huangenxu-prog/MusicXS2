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
                            VStack(alignment: .leading, spacing: 4) {
                                Text(id).font(.caption).lineLimit(1)
                                Text("已保存 · 未接入正式播放").font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("检查") { inspect(id: id) }
                                .buttonStyle(.bordered)
                        }
                    }
                    .onDelete(perform: delete)
                }
                Section {
                    Button("从文件导入 .js 音源") { isImporterPresented = true }
                }
                if let message {
                    Section("测试结果") { Text(message).font(.footnote).textSelection(.enabled) }
                }
            }
            .navigationTitle("音源测试")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } } }
            .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.javascript, .plainText], allowsMultipleSelection: false) { result in
                do {
                    guard let file = try result.get().first else { return }
                    let library = try getLibrary()
                    let script = try library.importScript(from: file)
                    reload()
                    message = "导入成功：\(script.filename)。请点击检查验证脚本初始化。"
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
        do { importedIDs = try getLibrary().listIdentifiers() }
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
