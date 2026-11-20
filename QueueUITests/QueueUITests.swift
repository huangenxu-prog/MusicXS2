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
        app.launchEnvironment["QUEUE_TEST_KIND"] = kind
        app.launchEnvironment["QUEUE_TEST_SONGS"] = json.base64EncodedString()
        app.launchEnvironment["QUEUE_TEST_IDS"] = ids
        app.launch()
        app.buttons["音乐库"].tap()
        app.buttons[favorites ? "收藏歌曲" : "最近播放"].tap()
        XCTAssertTrue(app.staticTexts["27 首"].waitForExistence(timeout: 8))
        let row = app.buttons["library-title-7"]
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<12 {
            if row.exists && row.frame.midY < app.frame.height * 0.70 && row.frame.midY > 80 { break }
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.64))
                .press(forDuration: 0.12, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48)), withVelocity: .slow, thenHoldForDuration: 0)
        }
        row.tap()
        let mini = app.buttons["mini-open-player"]
        XCTAssertTrue(mini.label.contains("FixtureTrack-8"), app.debugDescription)
        mini.tap()
        XCTAssertTrue(app.staticTexts["正在播放"].waitForExistence(timeout: 5), app.debugDescription)
        app.descendants(matching: .any).matching(identifier: "播放队列").firstMatch.tap()
        if !favorites {
            XCTAssertTrue(app.staticTexts["播放队列为空"].waitForExistence(timeout: 5), app.debugDescription)
            return
        }
        XCTAssertTrue(app.staticTexts["27 首"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["queue-row-FixtureTrack-1"].exists)
        XCTAssertTrue(app.buttons["queue-row-FixtureTrack-2"].exists)
        XCTAssertTrue(app.staticTexts["FixtureTrack-8"].exists)
    }
}
