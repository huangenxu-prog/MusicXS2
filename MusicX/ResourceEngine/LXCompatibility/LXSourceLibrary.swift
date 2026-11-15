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
        return try importScript(data: data, filename: filename)
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
        try Data(filename.utf8).write(to: directory.appendingPathComponent(id).appendingPathExtension("name"), options: .atomic)
        if selectedID == nil { selectedID = id }
        return Script(id: id, filename: filename, contents: text)
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
        return (try? String(contentsOf: url, encoding: .utf8)) ?? id
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

    private func scriptURL(for id: String) throws -> URL {
        guard UUID(uuidString: id) != nil else { throw LibraryError.invalidIdentifier }
        return directory.appendingPathComponent(id.lowercased()).appendingPathExtension("js")
    }
}
