import Foundation

/// Local script storage, independent from the UI and production playback pipeline.
/// Imported scripts are untrusted code and must only be executed by a restricted host.
@MainActor
final class LXSourceLibrary {
    struct Script: Identifiable, Sendable {
        let id: String
        let filename: String
        let contents: String
    }

    enum LibraryError: LocalizedError {
        case invalidFile
        case tooLarge
        case emptyScript
        case invalidIdentifier
        case htmlInsteadOfScript

        var errorDescription: String? {
            switch self {
            case .invalidFile: return "请选择 .js 音源文件"
            case .tooLarge: return "音源文件不能超过 2 MB"
            case .emptyScript: return "音源脚本内容为空"
            case .invalidIdentifier: return "音源标识无效"
            case .htmlInsteadOfScript: return "下载内容是 HTML 网页，不是 JS 音源。请使用 GitHub raw 原始直链，或检查代理地址。"
            }
        }
    }

    private struct BundledScript: Decodable {
        let id: String
        let name: String
        let contents: String
    }

    private func bundledScripts() -> [BundledScript] {
        guard let url = Bundle.main.url(forResource: "BundledLXSources", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let scripts = try? JSONDecoder().decode([BundledScript].self, from: data) else {
            return []
        }
        return scripts
    }

    func isBundled(id: String) -> Bool {
        bundledScripts().contains { $0.id == id }
    }

    private let selectedKey = "musicx.lx.selected-source.v1"
    private let approvedKey = "musicx.lx.approved-source-ids.v1"
    private let platformKey = "musicx.lx.enabled-platforms.v1"
    static let playbackPlatforms: Set<String> = ["tx", "wy", "kw", "kg"]
    private let directory: URL
    private let maximumSize = 2 * 1024 * 1024

    init(directory: URL? = nil) throws {
        let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.directory = root.appendingPathComponent("LXCustomSources", isDirectory: true)
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    @discardableResult
    func importScript(from file: URL) throws -> Script {
        guard file.pathExtension.lowercased() == "js" else { throw LibraryError.invalidFile }
        let granted = file.startAccessingSecurityScopedResource()
        defer { if granted { file.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: file, options: [.mappedIfSafe])
        guard data.count <= maximumSize else { throw LibraryError.tooLarge }
        guard let text = String(data: data, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LibraryError.emptyScript
        }
        return try importScript(data: data, filename: file.lastPathComponent)
    }

    @discardableResult
    func importScript(data: Data, filename: String) throws -> Script {
        guard filename.lowercased().hasSuffix(".js") else { throw LibraryError.invalidFile }
        guard data.count <= maximumSize else { throw LibraryError.tooLarge }
        guard let text = String(data: data, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LibraryError.emptyScript
        }
        guard !Self.looksLikeHTML(text) else { throw LibraryError.htmlInsteadOfScript }
        let id = UUID().uuidString.lowercased()
        let target = directory.appendingPathComponent(id).appendingPathExtension("js")
        try data.write(to: target, options: .atomic)
        let displayName = Self.displayFilename(script: text, fallback: filename)
        try Data(displayName.utf8).write(to: directory.appendingPathComponent(id).appendingPathExtension("name"), options: .atomic)
        if selectedID == nil { selectedID = id }
        return Script(id: id, filename: displayName, contents: text)
    }

    func listIdentifiers() throws -> [String] {
        let localIDs = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "js" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
        return bundledScripts().map(\.id) + localIDs
    }

    var selectedID: String? {
        get { UserDefaults.standard.string(forKey: selectedKey) }
        set { UserDefaults.standard.set(newValue, forKey: selectedKey) }
    }

    var approvedIDs: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: approvedKey) ?? [])
    }

    /// Per-source selection. Existing installed sources keep their old enabled
    /// platforms until the user explicitly changes a checkbox.
    private var platformOverrides: [String: [String]] {
        get { UserDefaults.standard.dictionary(forKey: platformKey) as? [String: [String]] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: platformKey) }
    }

    private struct SavedSource: Codable {
        let id: String
        let name: String
        let script: String
        let approved: Bool
        let platforms: [String]
    }

    private struct SourceArchive: Codable {
        let version: Int
        let savedAt: Date
        let imported: [SavedSource]
        let bundledPlatforms: [String: [String]]
    }

    /// Export actual JS text plus enablement flags; an iCloud/file backup can
    /// restore user-installed sources after reinstalling the app.
    func exportSourceArchive() throws -> Data {
        let ids = try listIdentifiers()
        let imported = try ids.filter { !isBundled(id: $0) }.map { id in
            SavedSource(
                id: id,
                name: try filename(id: id),
                script: try load(id: id),
                approved: approvedIDs.contains(id),
                platforms: enabledPlatforms(id: id).sorted()
            )
        }
        let bundled = Dictionary(uniqueKeysWithValues: ids.filter { isBundled(id: $0) }
            .map { ($0, enabledPlatforms(id: $0).sorted()) })
        let archive = SourceArchive(version: 1, savedAt: Date(),
                                    imported: imported, bundledPlatforms: bundled)
        return try JSONEncoder().encode(archive)
    }

    /// Merge an archive without deleting any existing source. Restore the
    /// archived UUID, name and platform switches so duplicates are not created.
    func restoreSourceArchive(_ data: Data) throws -> Int {
        guard data.count <= 30 * 1024 * 1024 else { throw LibraryError.tooLarge }
        let archive = try JSONDecoder().decode(SourceArchive.self, from: data)
        guard archive.version == 1, archive.imported.count <= 100 else {
            throw LibraryError.invalidFile
        }
        var seen = Set<String>()
        for item in archive.imported {
            guard UUID(uuidString: item.id) != nil,
                  seen.insert(item.id.lowercased()).inserted,
                  item.name.utf8.count <= 512,
                  item.script.utf8.count <= maximumSize,
                  !item.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !Self.looksLikeHTML(item.script),
                  Set(item.platforms).isSubset(of: Self.playbackPlatforms) else {
                throw LibraryError.invalidFile
            }
        }
        guard archive.bundledPlatforms.values.allSatisfy({
            Set($0).isSubset(of: Self.playbackPlatforms)
        }) else { throw LibraryError.invalidFile }

        for item in archive.imported {
            let id = item.id.lowercased()
            try Data(item.script.utf8).write(
                to: directory.appendingPathComponent(id).appendingPathExtension("js"),
                options: .atomic)
            try Data(item.name.utf8).write(
                to: directory.appendingPathComponent(id).appendingPathExtension("name"),
                options: .atomic)
        }
        var approved = approvedIDs
        var overrides = platformOverrides
        for item in archive.imported {
            let id = item.id.lowercased()
            if item.approved { approved.insert(id) } else { approved.remove(id) }
            overrides[id] = item.platforms.filter { Self.playbackPlatforms.contains($0) }
        }
        for (id, platforms) in archive.bundledPlatforms where isBundled(id: id) {
            overrides[id.lowercased()] = platforms
        }
        UserDefaults.standard.set(approved.sorted(), forKey: approvedKey)
        platformOverrides = overrides
        return archive.imported.count
    }

    func isJiexiang(id: String) -> Bool {
        guard let script = try? load(id: id) else { return false }
        let header = String(script.prefix(4096)).lowercased()
        return header.contains("@homepage https://github.com/haonanren118/jiexiang-music-source")
            && header.contains("@name 杰翔聚合音源")
    }

    func enabledPlatforms(id: String) -> Set<String> {
        let id = id.lowercased()
        let defaults: Set<String> = (isBundled(id: id) || approvedIDs.contains(id))
            ? Self.playbackPlatforms : []
        var enabled = Set(platformOverrides[id] ?? Array(defaults))
            .intersection(Self.playbackPlatforms)
        // Known invalid QQ prompt audio must never reach formal playback.
        if isJiexiang(id: id) { enabled.remove("tx") }
        return enabled
    }

    func setPlatformEnabled(id: String, platform: String, enabled: Bool) throws {
        guard Self.playbackPlatforms.contains(platform) else { throw LibraryError.invalidIdentifier }
        _ = try load(id: id)
        if enabled && platform == "tx" && isJiexiang(id: id) {
            throw LibraryError.invalidIdentifier
        }
        var current = enabledPlatforms(id: id)
        if enabled {
            current.insert(platform)
        } else {
            current.remove(platform)
        }
        var overrides = platformOverrides
        overrides[id.lowercased()] = current.sorted()
        platformOverrides = overrides
        // A checkbox can explicitly opt an imported script into playback.
        // Other platforms remain disabled unless selected or previously approved.
        if enabled && !isBundled(id: id) {
            try approve(id: id)
        }
    }

    func approve(id: String) throws {
        _ = try load(id: id)
        guard !isBundled(id: id) else { return }
        var ids = approvedIDs
        ids.insert(id.lowercased())
        UserDefaults.standard.set(Array(ids).sorted(), forKey: approvedKey)
    }

    func select(id: String) throws {
        if isBundled(id: id) {
            selectedID = id
            return
        }
        let url = try scriptURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { throw LibraryError.invalidIdentifier }
        selectedID = id.lowercased()
    }

    func filename(id: String) throws -> String {
        if let builtin = bundledScripts().first(where: { $0.id == id }) { return builtin.name }
        _ = try scriptURL(for: id)
        let url = directory.appendingPathComponent(id.lowercased()).appendingPathExtension("name")
        let stored = (try? String(contentsOf: url, encoding: .utf8)) ?? id
        if stored == "online-source.js" || stored == "latest.js" {
            let script = try load(id: id)
            let resolved = Self.displayFilename(script: script, fallback: stored)
            if resolved != stored {
                try? Data(resolved.utf8).write(to: url, options: .atomic)
            }
            return resolved
        }
        return stored
    }

    func load(id: String) throws -> String {
        if let builtin = bundledScripts().first(where: { $0.id == id }) { return builtin.contents }
        let url = try scriptURL(for: id)
        let text = try String(contentsOf: url, encoding: .utf8)
        guard !Self.looksLikeHTML(text) else { throw LibraryError.htmlInsteadOfScript }
        return text
    }

    func remove(id: String) throws {
        guard !isBundled(id: id) else { throw LibraryError.invalidIdentifier }
        var ids = approvedIDs
        ids.remove(id.lowercased())
        UserDefaults.standard.set(Array(ids).sorted(), forKey: approvedKey)
        var overrides = platformOverrides
        overrides.removeValue(forKey: id.lowercased())
        platformOverrides = overrides
        try FileManager.default.removeItem(at: scriptURL(for: id))
        let nameURL = directory.appendingPathComponent(id.lowercased()).appendingPathExtension("name")
        try? FileManager.default.removeItem(at: nameURL)
        if selectedID == id.lowercased() { selectedID = try listIdentifiers().first }
    }

    private static func looksLikeHTML(_ script: String) -> Bool {
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = trimmed.prefix(512).lowercased()
        return prefix.hasPrefix("<!doctype") || prefix.hasPrefix("<html") ||
            prefix.hasPrefix("<head") || prefix.hasPrefix("<body") ||
            prefix.hasPrefix("<?xml")
    }

    /// Extract LX source display metadata without executing untrusted JavaScript.
    /// The source header convention is: * @name Human-readable source name
    private static func displayFilename(script: String, fallback: String) -> String {
        let header = String(script.prefix(4096))
        let pattern = #"(?m)^\s*\*\s*@name\s+([^\r\n]+)"#
        if let range = header.range(of: pattern, options: .regularExpression) {
            let line = String(header[range])
            if let marker = line.range(of: "@name") {
                let name = line[marker.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: #"\s*\*/\s*$"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { return String(name.prefix(80)) }
            }
        }
        return fallback
    }

    private func scriptURL(for id: String) throws -> URL {
        guard UUID(uuidString: id) != nil else { throw LibraryError.invalidIdentifier }
        return directory.appendingPathComponent(id.lowercased()).appendingPathExtension("js")
    }
}
