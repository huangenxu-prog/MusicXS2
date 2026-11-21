import UIKit
import UniformTypeIdentifiers

enum BackupClipboard {
    @MainActor
    static func read() async throws -> Data {
        let board = UIPasteboard.general
        let providers = board.itemProviders
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.json.identifier) }) {
            return try await withCheckedThrowingContinuation { continuation in
                provider.loadFileRepresentation(forTypeIdentifier: UTType.json.identifier) { url, error in
                    do {
                        guard let url else { throw error ?? CocoaError(.fileReadUnknown) }
                        continuation.resume(returning: try Data(contentsOf: url))
                    } catch { continuation.resume(throwing: error) }
                }
            }
        }
        if let url = board.url, url.isFileURL {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            return try Data(contentsOf: url)
        }
        if let text = board.string, !text.isEmpty { return Data(text.utf8) }
        throw NSError(domain: "MusicX.BackupClipboard", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "请先复制 JSON 备份文件，或复制文件里的完整 JSON 文本。"
        ])
    }
}
