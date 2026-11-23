import SwiftUI
import UniformTypeIdentifiers

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

/// Light reference screen 13. The existing LXSourceLibrary remains the sole source of truth.
/// The advanced script inspection / playback approval flow stays in LXSourceTestPanel.
struct MXReferenceSources: View {
    @Environment(\.dismiss) private var dismiss

    private struct SourceItem: Identifiable {
        let id: String
        let name: String
        let platforms: Set<String>
        let approved: Bool
    }
    @State private var sourceItems: [SourceItem] = []
    @State private var message: String?
    @State private var isSyncing = false
    @State private var showJSImporter = false
    @State private var showBackupImporter = false
    @State private var showBackupExporter = false
    @State private var showURLImporter = false
    @State private var showAdvanced = false
    @State private var remoteURL = ""
    @State private var backupDocument: MXReferenceSourceDocument?

    private let cloudURL =
        "https://raw.githubusercontent.com/huangenxu-prog/MusicXS2/test/build-486-complete-source/MusicX/CloudSources.json"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 40, height: 42, alignment: .leading)
                }
                Spacer()
                Text("音源管理").font(.system(size: 16, weight: .bold))
                Spacer()
                // Advanced testing has one explicit row below; no duplicate top menu.
                Color.clear.frame(width: 40, height: 42)
                    .accessibilityHidden(true)
            }
            .font(.system(size: 19))
            .foregroundStyle(MXLight.ink)
            .padding(.horizontal, 24)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("云端同步会更新本地音源配置。新导入的 JS 音源需先通过试听验证，才能用于正式播放。")
                        .font(.system(size: 12))
                        .foregroundStyle(MXLight.muted)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(MXLight.cream, in: RoundedRectangle(cornerRadius: 13))

                    VStack(spacing: 0) {
                        actionRow("云端同步音源", icon: "cloud") {
                            Task { await syncCloud() }
                        }
                        MXLight.line.frame(height: 0.5)
                        Menu {
                            Button("从文件导入 JS 音源", systemImage: "doc") {
                                showJSImporter = true
                            }
                            Button("从网址导入 JS 音源", systemImage: "link") {
                                remoteURL = ""
                                showURLImporter = true
                            }
                        } label: {
                            actionLabel("导入音源", icon: "plus")
                        }
                        MXLight.line.frame(height: 0.5)
                        actionRow("音源测试与高级管理", icon: "checkmark.shield") {
                            showAdvanced = true
                        }
                        MXLight.line.frame(height: 0.5)
                        Menu {
                            Button("导出音源配置备份", systemImage: "square.and.arrow.up",
                                   action: exportBackup)
                            Button("从本地备份恢复", systemImage: "square.and.arrow.down") {
                                showBackupImporter = true
                            }
                        } label: {
                            actionLabel("音源配置备份", icon: "externaldrive")
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(MXLight.paper, in: RoundedRectangle(cornerRadius: 18))
                    .padding(.top, 20)

                    if isSyncing {
                        ProgressView("正在同步音源")
                            .tint(MXLight.teal).padding(.vertical, 14)
                    }
                    if let message {
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundStyle(MXLight.muted)
                            .padding(.top, 12)
                    }

                    section("已导入音源", right: "\(sourceItems.count) 条")
                    if sourceItems.isEmpty {
                        Text("尚未导入音源")
                            .font(.system(size: 13))
                            .foregroundStyle(MXLight.muted)
                            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                    }
                    ForEach(Array(sourceItems.enumerated()), id: \.element.id) { i, item in
                        HStack(spacing: 11) {
                            Image(systemName: "music.note")
                                .font(.system(size: 17))
                                .foregroundStyle(i % 2 == 0 ? MXLight.teal : MXLight.ink)
                                .frame(width: 34, height: 34)
                                .background(i % 2 == 0 ? MXLight.lightTeal :
                                             MXLight.cream, in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(MXLight.ink).lineLimit(1)
                                Text(item.approved
                                     ? displayPlatforms(item.platforms)
                                     : "待试听验证 · 尚未正式启用")
                                    .font(.system(size: 11))
                                    .foregroundStyle(MXLight.muted)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Toggle(item.name, isOn: Binding(
                                get: { item.approved && !item.platforms.isEmpty },
                                set: { enabled in setSource(item.id, enabled: enabled) }
                            ))
                            .labelsHidden()
                            .tint(MXLight.teal)
                            .disabled(!item.approved)
                        }
                        .padding(.vertical, 9)
                        MXLight.line.frame(height: 0.5)
                    }

                    Text("已批准的音源可直接启停；测试、平台通道细节与删除操作统一在「音源测试与高级管理」中处理。")
                        .font(.system(size: 11))
                        .foregroundStyle(MXLight.muted)
                        .padding(.top, 18)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 30)
            }
        }
        .background(MXLight.background.ignoresSafeArea())
        .preferredColorScheme(.light)
        .onAppear(perform: reload)
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

    private func section(_ title: String, right: String? = nil) -> some View {
        HStack {
            Text(title).font(.system(size: 15, weight: .bold))
                .tracking(1.4).foregroundStyle(MXLight.headingMuted)
            Spacer()
            if let right {
                Text(right).font(.system(size: 12)).foregroundStyle(MXLight.muted)
            }
        }
        .padding(.top, 25)
        .padding(.bottom, 13)
    }

    private func actionLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .frame(width: 34, height: 34)
                .background(MXLight.cream, in: Circle())
            Text(title).font(.system(size: 14, weight: .semibold))
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13))
        }
        .foregroundStyle(MXLight.ink)
        .frame(height: 57)
        .contentShape(Rectangle())
    }

    private func actionRow(_ title: String, icon: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            actionLabel(title, icon: icon)
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

    @MainActor private func setSource(_ id: String, enabled: Bool) {
        do {
            let lib = try LXSourceLibrary()
            guard lib.isBundled(id: id) ||
                  lib.approvedIDs.contains(id.lowercased()) else {
                message = "请先在高级测试中试听并批准该音源。"
                return
            }
            for platform in LXSourceLibrary.playbackPlatforms {
                try lib.setPlatformEnabled(id: id, platform: platform, enabled: enabled)
            }
            message = enabled ? "已启用对应通道" : "已停用对应通道"
            reload()
        } catch {
            message = "修改失败：\(error.localizedDescription)"
        }
    }

    private func displayPlatforms(_ platforms: Set<String>) -> String {
        if platforms.isEmpty { return "全部停用" }
        let names = ["tx": "QQ", "wy": "网易云", "kw": "酷我", "kg": "酷狗"]
        return platforms.sorted().map { names[$0] ?? $0 }.joined(separator: " · ")
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
            let (data, response) = try await URLSession.shared.data(
                from: url, delegate: nil)
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
