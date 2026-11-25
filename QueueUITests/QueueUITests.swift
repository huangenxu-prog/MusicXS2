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
        let mini = app.buttons["mini-open-player"]
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        // The eighth row may be covered by the floating mini player even
        // when XCTest reports it as hittable. Scroll it above that overlay.
        for _ in 0..<5 {
            if row.isHittable && row.frame.maxY < mini.frame.minY - 12 { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        guard row.isHittable && row.frame.maxY < mini.frame.minY - 12 else {
            XCTFail("Selected track is not safely above the mini player: \(app.debugDescription)")
            return
        }
        row.tap()
        let selected = NSPredicate(format: "label CONTAINS %@", "FixtureTrack-8")
        let ready = XCTNSPredicateExpectation(predicate: selected, object: mini)
        guard XCTWaiter.wait(for: [ready], timeout: 10) == .completed else {
            XCTFail("Mini player did not select FixtureTrack-8: \(app.debugDescription)")
            return
        }
        mini.tap()
        let queueButton = app.buttons["player-open-queue"]
        guard queueButton.waitForExistence(timeout: 10) else {
            XCTFail("Player queue control not found: \(app.debugDescription)")
            return
        }
        queueButton.tap()
        // Recent Plays and Favorites must both build the full 27-song queue.
        // The previous test incorrectly locked in an empty Recent queue.
        XCTAssertTrue(app.staticTexts["27 首"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["queue-row-FixtureTrack-1"].exists)
        XCTAssertTrue(app.buttons["queue-row-FixtureTrack-2"].exists)
        XCTAssertTrue(app.staticTexts["FixtureTrack-8"].exists)
    }
}
