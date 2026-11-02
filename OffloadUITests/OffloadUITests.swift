import XCTest

final class OffloadUITests: XCTestCase {
    var app: XCUIApplication!
    var state: XCUIElement { app.descendants(matching: .any)["reviewState"].firstMatch }
    var card: XCUIElement { app.descendants(matching: .any)["photoCard"].firstMatch }
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(); app.resetAuthorizationStatus(for: .photos)
        app.launchArguments = ["--uitesting"]; app.launch()
        if app.buttons["tutorialSkip"].waitForExistence(timeout: 2) { app.buttons["tutorialSkip"].tap() }
    }
    func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func command(_ name: String) { app.open(URL(string: "offload-test://\(name)")!) }
    func start(paused: Bool = true) {
        app.buttons["start"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["Allow Full Access"].waitForExistence(timeout: 3) { springboard.buttons["Allow Full Access"].tap() }
        else if app.buttons["Allow Full Access"].exists { app.buttons["Allow Full Access"].tap() }
        XCTAssertTrue(app.buttons["pause"].waitForExistence(timeout: 30))
        if paused { app.buttons["pause"].tap() }
        XCTAssertTrue(card.waitForExistence(timeout: 20))
    }
    func waitForState(_ text: String) {
        expectation(for: NSPredicate(format: "value CONTAINS %@", text), evaluatedWith: state)
        waitForExpectations(timeout: 12)
    }
    func testSwipeArchiveKeepUndoAndRemoval() {
        screenshot("01-start")
        command("connect"); start()
        screenshot("02-photo-review")
        card.swipeLeft(); waitForState("1 archived")
        screenshot("03-verified-copy")
        card.swipeRight(); waitForState("1 kept")
        app.buttons["undo"].tap(); waitForState("0 kept")
        app.buttons["reviewRemoval"].tap(); screenshot("04-removal-confirmation")
        app.buttons["Cancel"].tap(); waitForState("1 archived")
        app.buttons["reviewRemoval"].tap(); app.buttons["confirmRemoval"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.alerts.firstMatch.waitForExistence(timeout: 8) {
            let delete = springboard.alerts.firstMatch.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Delete'")).firstMatch
            if delete.exists { delete.tap() }
        }
        let delete = app.alerts.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Delete'")).firstMatch
        if delete.exists { delete.tap() }
        waitForState("0 archived"); screenshot("05-removal-complete")
    }
    func testDisconnectedDriveAndCorruptCopyBlockRemoval() {
        start()
        card.swipeLeft()
        XCTAssertTrue(app.alerts["Couldn't finish"].waitForExistence(timeout: 5))
        waitForState("0 archived"); screenshot("06-no-drive-blocked")
        app.buttons["OK"].tap(); command("internal")
        XCTAssertTrue(app.alerts["Couldn't finish"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.staticTexts.matching(NSPredicate(format: "label CONTAINS 'External drive could not be confirmed'")).firstMatch.exists)
        screenshot("11-internal-folder-rejected"); app.buttons["OK"].tap()
        command("connect"); card.swipeLeft(); waitForState("1 archived")
        command("disconnect")
        app.buttons["reviewRemoval"].tap(); app.buttons["confirmRemoval"].tap()
        XCTAssertTrue(app.alerts["Couldn't finish"].waitForExistence(timeout: 5))
        screenshot("07-disconnected-removal-blocked"); app.buttons["OK"].tap()
        command("connect"); command("corrupt")
        app.buttons["reviewRemoval"].tap(); app.buttons["confirmRemoval"].tap()
        XCTAssertTrue(app.alerts["Couldn't finish"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Archive changed'")).firstMatch.exists)
        waitForState("1 archived"); screenshot("08-corruption-blocked")
    }
    func testFiveSecondTimeoutKeepsPhoto() {
        start(paused: false); waitForState("1 kept")
        app.buttons["pause"].tap(); waitForState("0 archived")
        screenshot("09-timeout-keeps-photo")
    }
    func testSwipePreservesAutomaticTimer() {
        command("connect"); start(paused: false)
        card.swipeLeft(); waitForState("1 archived")
        XCTAssertEqual(app.buttons["pause"].label, "Pause review")
        waitForState("1 kept"); app.buttons["pause"].tap()
        screenshot("12-timer-continues-after-swipe")
    }
    func testFirstLaunchTutorialSwipesAndStaysDismissed() {
        app.terminate(); app.launchArguments = ["--uitesting", "--show-tutorial"]; app.launch()
        XCTAssertTrue(app.staticTexts["tutorialStep"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["tutorialStep"].label.hasPrefix("1 of 4")); screenshot("13-tutorial-connect-drive")
        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["tutorialStep"].label.hasPrefix("2 of 4")); screenshot("14-tutorial-swipe-left")
        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["tutorialStep"].label.hasPrefix("3 of 4")); screenshot("15-tutorial-swipe-right")
        app.buttons["tutorialNext"].tap()
        XCTAssertTrue(app.staticTexts["tutorialStep"].label.hasPrefix("4 of 4")); screenshot("16-tutorial-removal")
        app.buttons["tutorialBegin"].tap()
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments = ["--uitesting"]; app.launch()
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["tutorialSkip"].exists)
        app.buttons["showTutorial"].tap()
        XCTAssertTrue(app.staticTexts["tutorialStep"].waitForExistence(timeout: 5))
        app.buttons["tutorialSkip"].tap()
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 5))
    }
}
