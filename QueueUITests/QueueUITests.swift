import XCTest

final class QueueUITests: XCTestCase {
    func testFavoriteQueue() throws { try checkQueue(favorites: true) }
    func testRecentQueue() throws { try checkQueue(favorites: false) }

    private func checkQueue(favorites: Bool) throws {
        let app = XCUIApplication()
        let tracks = (1...27).map { ["source": "wy", "sourceID": String($0),
                                     "title": "FixtureTrack-\($0)", "artist": "Queue Artist"] }
        let json = try JSONSerialization.data(withJSONObject: tracks)
        let ids = tracks.map { track in
            let hash = ("wy:" + track["sourceID"]!).utf8.reduce(UInt64(14695981039346656037)) {
                ($0 ^ UInt64($1)) &* 1099511628211
            }
            return String(hash & 0x7fffffffffffffff)
        }.joined(separator: ",")
        let kind = favorites ? "favorite" : "recent"
        app.launchArguments = ["-musicx.\(kind)Songs", String(decoding: json, as: UTF8.self),
                               "-musicx.\(kind)IDs", ids]
        app.launch()
        app.buttons["音乐库"].tap()
        app.buttons[favorites ? "收藏歌曲" : "最近播放"].tap()
        XCTAssertTrue(app.staticTexts["27 首"].waitForExistence(timeout: 8))
        let row = app.buttons["library-title-7"]
        for _ in 0..<5 where !row.isHittable { app.scrollViews.firstMatch.swipeUp() }
        row.tap()
        app.buttons["mini-open-player"].tap()
        app.buttons["播放队列"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["20 首"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["queue-row-FixtureTrack-8"].exists)
        XCTAssertTrue(app.buttons["queue-row-FixtureTrack-9"].exists)
        XCTAssertFalse(app.buttons["queue-row-FixtureTrack-7"].exists)
    }
}
