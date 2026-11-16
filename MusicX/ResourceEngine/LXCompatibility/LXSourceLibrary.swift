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

        var errorDescription: String? {
            switch self {
            case .invalidFile: return "请选择 .js 音源文件"
            case .tooLarge: return "音源文件不能超过 2 MB"
            case .emptyScript: return "音源脚本内容为空"
            case .invalidIdentifier: return "音源标识无效"
            }
        }
    }

    private let selectedKey = "musicx.lx.selected-source.v1"
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
        let id = UUID().uuidString.lowercased()
        let target = directory.appendingPathComponent(id).appendingPathExtension("js")
        try data.write(to: target, options: .atomic)
        let displayName = Self.displayFilename(script: text, fallback: filename)
        try Data(displayName.utf8).write(to: directory.appendingPathComponent(id).appendingPathExtension("name"), options: .atomic)
        if selectedID == nil { selectedID = id }
        return Script(id: id, filename: displayName, contents: text)
    }

    func listIdentifiers() throws -> [String] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "js" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    var selectedID: String? {
        get { UserDefaults.standard.string(forKey: selectedKey) }
        set { UserDefaults.standard.set(newValue, forKey: selectedKey) }
    }

    func select(id: String) throws {
        let url = try scriptURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { throw LibraryError.invalidIdentifier }
        selectedID = id.lowercased()
    }

    func filename(id: String) throws -> String {
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
        let url = try scriptURL(for: id)
        return try String(contentsOf: url, encoding: .utf8)
    }

    func remove(id: String) throws {
        try FileManager.default.removeItem(at: scriptURL(for: id))
        let nameURL = directory.appendingPathComponent(id.lowercased()).appendingPathExtension("name")
        try? FileManager.default.removeItem(at: nameURL)
        if selectedID == id.lowercased() { selectedID = try listIdentifiers().first }
    }

    /// Extract LX source display metadata without executing untrusted JavaScript.
    /// The source header convention is: * @name Human-readable source name
    private static func displayFilename(script: String, fallback: String) -> String {
        let header = String(script.prefix(4096))
        let pattern = #"(?m)^\\s*\\*\\s*@name\\s+([^\\r\\n]+)"#
        if let range = header.range(of: pattern, options: .regularExpression) {
            let line = String(header[range])
            if let marker = line.range(of: "@name") {
                let name = line[marker.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: #"\\s*\\*/\\s*$"#, with: "", options: .regularExpression)
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
