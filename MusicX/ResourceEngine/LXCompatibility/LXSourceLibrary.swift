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
        // A previous restore can have been interrupted between directory moves.
        // Recover the previous snapshot before allowing any new source reads.
        try recoverInterruptedRestore()
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

    /// Archive restores first build a complete sibling directory, then swap it
    /// into place. A small journal allows the next app launch to roll back if
    /// iOS kills the process between the two filesystem moves.
    private struct RestoreJournal: Codable {
        let stagedName: String
        let oldApproved: [String]?
        let oldPlatforms: [String: [String]]?
        let oldSelected: String?
    }

    private var restoreBackupURL: URL {
        directory.deletingLastPathComponent()
            .appendingPathComponent("LXCustomSources.restore-backup", isDirectory: true)
    }

    private var restoreJournalURL: URL {
        directory.deletingLastPathComponent()
            .appendingPathComponent("LXCustomSources.restore-journal.json")
    }

    private func restoreOldPreferences(from journal: RestoreJournal) {
        let defaults = UserDefaults.standard
        if let old = journal.oldApproved {
            defaults.set(old, forKey: approvedKey)
        } else {
            defaults.removeObject(forKey: approvedKey)
        }
        if let old = journal.oldPlatforms {
            defaults.set(old, forKey: platformKey)
        } else {
            defaults.removeObject(forKey: platformKey)
        }
        if let old = journal.oldSelected {
            defaults.set(old, forKey: selectedKey)
        } else {
            defaults.removeObject(forKey: selectedKey)
        }
    }

    /// Complete rollback, including platform checkboxes, before using sources.
    private func recoverInterruptedRestore() throws {
        let fm = FileManager.default
        let backup = restoreBackupURL
        let journalURL = restoreJournalURL
        guard fm.fileExists(atPath: journalURL.path) else {
            // Journal removed means the new sources and settings were committed.
            // A leftover backup is just cleanup from a completed transaction.
            if fm.fileExists(atPath: backup.path) {
                if fm.fileExists(atPath: directory.path) {
                    try fm.removeItem(at: backup)
                } else {
                    try fm.moveItem(at: backup, to: directory)
                }
            }
            return
        }

        let journal = try JSONDecoder().decode(
            RestoreJournal.self, from: Data(contentsOf: journalURL)
        )
        // Only clean up a staging folder generated by this library.
        guard journal.stagedName.hasPrefix("LXCustomSources.restore-stage-"),
              !journal.stagedName.contains("/"),
              !journal.stagedName.contains("..") else {
            throw LibraryError.invalidFile
        }
        let staged = directory.deletingLastPathComponent()
            .appendingPathComponent(journal.stagedName, isDirectory: true)

        if fm.fileExists(atPath: backup.path) {
            if fm.fileExists(atPath: directory.path) {
                try fm.removeItem(at: directory)
            }
            try fm.moveItem(at: backup, to: directory)
        }
        restoreOldPreferences(from: journal)
        if fm.fileExists(atPath: staged.path) {
            try fm.removeItem(at: staged)
        }
        try fm.removeItem(at: journalURL)
    }

    /// Merge or replace imported JS files without leaving a partially applied
    /// collection if writing the staged archive fails. A successful restore
    /// includes the exact per-platform checkboxes in the supplied backup.
    func restoreSourceArchive(_ data: Data, replaceImported: Bool = false) throws -> Int {
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

        let fm = FileManager.default
        let stage = directory.deletingLastPathComponent()
            .appendingPathComponent("LXCustomSources.restore-stage-\(UUID().uuidString)",
                                    isDirectory: true)
        // Copy first to preserve manually imported files when restoring a
        // local backup; cloud synchronization removes only unlisted JS files.
        try fm.copyItem(at: directory, to: stage)
        defer {
            if fm.fileExists(atPath: stage.path) {
                try? fm.removeItem(at: stage)
            }
        }

        let staleIDs = replaceImported ? try listIdentifiers().filter {
            !isBundled(id: $0) && !seen.contains($0.lowercased())
        } : []
        for id in staleIDs {
            let key = id.lowercased()
            for ext in ["js", "name"] {
                let file = stage.appendingPathComponent(key).appendingPathExtension(ext)
                if fm.fileExists(atPath: file.path) {
                    try fm.removeItem(at: file)
                }
            }
        }
        for item in archive.imported {
            let id = item.id.lowercased()
            try Data(item.script.utf8).write(
                to: stage.appendingPathComponent(id).appendingPathExtension("js"),
                options: .atomic)
            try Data(item.name.utf8).write(
                to: stage.appendingPathComponent(id).appendingPathExtension("name"),
                options: .atomic)
        }

        var nextApproved = approvedIDs
        var nextOverrides = platformOverrides
        for id in staleIDs {
            nextApproved.remove(id.lowercased())
            nextOverrides.removeValue(forKey: id.lowercased())
        }
        for item in archive.imported {
            let id = item.id.lowercased()
            if item.approved { nextApproved.insert(id) }
            else { nextApproved.remove(id) }
            nextOverrides[id] = item.platforms.sorted()
        }
        for (id, platforms) in archive.bundledPlatforms where isBundled(id: id) {
            nextOverrides[id.lowercased()] = platforms.sorted()
        }

        var nextSelected = selectedID
        if replaceImported, let selected = nextSelected,
           staleIDs.contains(where: { $0.lowercased() == selected.lowercased() }) {
            nextSelected = archive.imported.first?.id.lowercased()
                ?? bundledScripts().first?.id
        }

        let defaults = UserDefaults.standard
        let journal = RestoreJournal(
            stagedName: stage.lastPathComponent,
            oldApproved: defaults.stringArray(forKey: approvedKey),
            oldPlatforms: defaults.dictionary(forKey: platformKey) as? [String: [String]],
            oldSelected: defaults.string(forKey: selectedKey)
        )
        // Do not touch the live folder until every file is written and the
        // recoverable snapshot has been saved.
        try JSONEncoder().encode(journal).write(to: restoreJournalURL, options: .atomic)
        do {
            try fm.moveItem(at: directory, to: restoreBackupURL)
            try fm.moveItem(at: stage, to: directory)
            defaults.set(nextApproved.sorted(), forKey: approvedKey)
            defaults.set(nextOverrides, forKey: platformKey)
            if let nextSelected { defaults.set(nextSelected, forKey: selectedKey) }
            else { defaults.removeObject(forKey: selectedKey) }

            // The commit point: after this, an old backup can be safely removed.
            try fm.removeItem(at: restoreJournalURL)
        } catch {
            // Recovery also runs during init if the process is terminated here.
            try? recoverInterruptedRestore()
            throw error
        }
        // Failure to clean a committed backup must never report a false
        // restore failure; initialization will clean the leftover next time.
        try? fm.removeItem(at: restoreBackupURL)
        return archive.imported.count
    }

    func enabledPlatforms(id: String) -> Set<String> {
        let id = id.lowercased()
        let defaults: Set<String> = (isBundled(id: id) || approvedIDs.contains(id))
            ? Self.playbackPlatforms : []
        var enabled = Set(platformOverrides[id] ?? Array(defaults))
            .intersection(Self.playbackPlatforms)
        return enabled
    }

    func setPlatformEnabled(id: String, platform: String, enabled: Bool) throws {
        guard Self.playbackPlatforms.contains(platform) else { throw LibraryError.invalidIdentifier }
        _ = try load(id: id)
        var current = enabledPlatforms(id: id)
        if enabled {
            current.insert(platform)
        } else {
            current.remove(platform)
        }
        var overrides = platformOverrides
        overrides[id.lowercased()] = current.sorted()
        platformOverrides = overrides
        // Checkboxes never bypass the audio preview approval gate.
        // Unapproved scripts can record preferences but cannot play until tested.
    }

    func approve(id: String, testedPlatform: String? = nil) throws {
        _ = try load(id: id)
        guard !isBundled(id: id) else { return }
        var ids = approvedIDs
        let key = id.lowercased()
        let wasApproved = ids.contains(key)
        ids.insert(key)
        UserDefaults.standard.set(Array(ids).sorted(), forKey: approvedKey)
        // On first preview, opt in only the platform actually tested.
        // Existing approved installs keep their previous selections.
        if !wasApproved, let testedPlatform,
           Self.playbackPlatforms.contains(testedPlatform) {
            var overrides = platformOverrides
            var selected = Set(overrides[key] ?? [])
            selected.insert(testedPlatform)
            overrides[key] = selected.sorted()
            platformOverrides = overrides
        }
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
