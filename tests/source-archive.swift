import Foundation

/// Runs as a Foundation-only macOS smoke test in GitHub Actions.
@main
struct LXSourceArchiveTests {
    @MainActor
    static func main() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("MusicXSourceArchiveTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let keys = [
            "musicx.lx.selected-source.v1",
            "musicx.lx.approved-source-ids.v1",
            "musicx.lx.enabled-platforms.v1"
        ]
        defer {
            try? fileManager.removeItem(at: root)
            keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        }
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }

        let library = try LXSourceLibrary(directory: root)
        let old = try library.importScript(
            data: Data("/* @name Original */\nconsole.log('old');".utf8),
            filename: "original.js"
        )
        try library.approve(id: old.id, testedPlatform: "tx")
        try library.setPlatformEnabled(id: old.id, platform: "kg", enabled: false)
        let oldScript = try library.load(id: old.id)

        let replacementID = UUID().uuidString.lowercased()
        func makeArchive(items: [[String: Any]]) throws -> Data {
            let exported = try library.exportSourceArchive()
            var document = try JSONSerialization.jsonObject(with: exported) as! [String: Any]
            document["imported"] = items
            return try JSONSerialization.data(withJSONObject: document)
        }
        let replacement: [String: Any] = [
            "id": replacementID, "name": "Cloud Replacement",
            "script": "/* @name Cloud Replacement */\nconsole.log('replacement');",
            "approved": true, "platforms": ["wy"]
        ]
        let valid = try makeArchive(items: [replacement])

        // Invalid archives cannot replace or delete the user's existing files.
        var invalid = replacement
        invalid["script"] = "<html>not a JS script</html>"
        do {
            _ = try library.restoreSourceArchive(try makeArchive(items: [invalid]),
                                                 replaceImported: true)
            preconditionFailure("Invalid source archive was accepted")
        } catch {
            precondition(try library.load(id: old.id) == oldScript)
            precondition(library.enabledPlatforms(id: old.id) == ["tx"])
        }

        precondition(try library.restoreSourceArchive(valid, replaceImported: true) == 1)
        precondition(try library.listIdentifiers() == [replacementID])
        precondition((try library.load(id: replacementID)).contains("replacement"))
        precondition(library.approvedIDs == [replacementID])
        precondition(library.enabledPlatforms(id: replacementID) == ["wy"])
        precondition(library.selectedID == replacementID)
        precondition(!fileManager.fileExists(
            atPath: root.appendingPathComponent("LXCustomSources.restore-journal.json").path))

        // A normal local restore merges sources rather than replacing existing ones.
        let merged = try library.restoreSourceArchive(try makeArchive(items: [
            ["id": old.id, "name": "Original", "script": oldScript,
             "approved": true, "platforms": ["tx"]]
        ]))
        precondition(merged == 1)
        precondition(Set(try library.listIdentifiers()) == [old.id, replacementID])

        // Simulate process termination after the staged files have replaced the
        // live folder but before metadata has committed. Init must restore both.
        let live = root.appendingPathComponent("LXCustomSources", isDirectory: true)
        let backup = root.appendingPathComponent("LXCustomSources.restore-backup", isDirectory: true)
        let journal = root.appendingPathComponent("LXCustomSources.restore-journal.json")
        try fileManager.moveItem(at: live, to: backup)
        try fileManager.createDirectory(at: live, withIntermediateDirectories: true)
        try Data("bad".utf8).write(
            to: live.appendingPathComponent(UUID().uuidString.lowercased()).appendingPathExtension("js")
        )
        let journalJSON: [String: Any] = [
            "stagedName": "LXCustomSources.restore-stage-test",
            "oldApproved": [old.id, replacementID],
            "oldPlatforms": [old.id: ["tx"], replacementID: ["wy"]],
            "oldSelected": replacementID
        ]
        try JSONSerialization.data(withJSONObject: journalJSON)
            .write(to: journal, options: .atomic)
        UserDefaults.standard.set(["wrong-id"], forKey: "musicx.lx.approved-source-ids.v1")
        let recovered = try LXSourceLibrary(directory: root)
        precondition(Set(try recovered.listIdentifiers()) == [old.id, replacementID])
        precondition(recovered.approvedIDs == [old.id, replacementID])
        precondition(recovered.enabledPlatforms(id: replacementID) == ["wy"])
        precondition(recovered.selectedID == replacementID)
        precondition(!fileManager.fileExists(atPath: journal.path))
        precondition(!fileManager.fileExists(atPath: backup.path))
        print("LX source archive restore and interrupted-restore recovery passed")
    }
}
