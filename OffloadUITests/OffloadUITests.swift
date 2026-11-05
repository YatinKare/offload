import XCTest

final class OffloadUITests: XCTestCase {
    var app: XCUIApplication!
    var state: XCUIElement { app.descendants(matching: .any)["reviewState"].firstMatch }
    var card: XCUIElement { app.descendants(matching: .any)["photoCard"].firstMatch }
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(); app.resetAuthorizationStatus(for: .photos)
        app.launchArguments = ["--uitesting", "--reset-session"]; app.launch()
        if app.buttons["tutorialSkip"].waitForExistence(timeout: 2) { app.buttons["tutorialSkip"].tap() }
    }
    func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
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
        expectation(for: NSPredicate(format: "value CONTAINS %@", text), evaluatedWith: state); waitForExpectations(timeout: 12)
    }
    func openArchive() {
        app.buttons["reviewRemoval"].tap(); XCTAssertTrue(app.navigationBars["Archive"].waitForExistence(timeout: 5))
    }
    func confirmRemoval() {
        app.buttons["verifyArchive"].tap()
        XCTAssertTrue(app.buttons["confirmRemoval"].waitForExistence(timeout: 12))
        app.buttons["confirmRemoval"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let delete = springboard.alerts.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Delete'")).firstMatch
        if delete.waitForExistence(timeout: 8) { delete.tap() }
        else {
            let appDelete = app.alerts.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Delete'")).firstMatch
            if appDelete.exists { appDelete.tap() }
        }
        XCTAssertTrue(app.staticTexts["Archive is empty"].waitForExistence(timeout: 12))
    }
    func testSwipeArchiveKeepUndoAndRemoval() {
        command("connect"); start(); screenshot("01-review")
        card.swipeLeft(); waitForState("1 archived")
        card.swipeRight(); waitForState("1 kept")
        app.buttons["undo"].tap(); waitForState("0 kept")
        openArchive(); screenshot("02-archive-list")
        app.buttons["verifyArchive"].tap()
        XCTAssertTrue(app.buttons["confirmRemoval"].waitForExistence(timeout: 12)); app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["archiveItem"].firstMatch.exists)
        confirmRemoval(); screenshot("03-removed")
    }
    func testDisconnectedDriveAndCorruptCopyBlockRemoval() {
        start(); card.swipeLeft()
        XCTAssertTrue(app.alerts["Couldn't finish"].waitForExistence(timeout: 5)); app.buttons["OK"].tap()
        command("internal")
        XCTAssertTrue(app.alerts["Couldn't finish"].waitForExistence(timeout: 5)); app.buttons["OK"].tap()
        command("connect"); card.swipeLeft(); waitForState("1 archived")
        command("disconnect"); openArchive()
        XCTAssertTrue(app.buttons["verifyArchive"].exists); XCTAssertEqual(app.buttons["verifyArchive"].label, "Connect drive")
        app.buttons["Done"].tap(); command("connect"); command("corrupt")
        openArchive(); app.buttons["verifyArchive"].tap()
        XCTAssertTrue(app.staticTexts["archiveNotice"].waitForExistence(timeout: 12))
        XCTAssertFalse(app.buttons["confirmRemoval"].exists)
        app.buttons["archiveItem"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["itemIssue"].waitForExistence(timeout: 5)); screenshot("04-corruption-recovery")
        app.buttons["keepArchivedOnPhone"].tap()
        XCTAssertTrue(app.staticTexts["Archive is empty"].waitForExistence(timeout: 5))
    }
    func testFiveSecondTimeoutKeepsPhoto() {
        start(paused: false); waitForState("1 kept"); app.buttons["pause"].tap(); waitForState("0 archived")
    }
    func testSlowArchiveDoesNotBlockNextPhoto() {
        app.terminate(); app.launchArguments = ["--uitesting", "--reset-session", "--slow-archive"]; app.launch()
        command("connect"); start(paused: false)
        card.swipeLeft()
        XCTAssertTrue(app.staticTexts["2/3"].waitForExistence(timeout: 2), "Review must advance before the slow copy finishes")
        waitForState("1 pending"); screenshot("05-copy-pending-review-continues")
        card.swipeRight(); waitForState("1 kept")
        XCTAssertEqual(app.buttons["pause"].label, "Pause review")
        // The timer also keeps reviewing while a copy is outstanding.
        waitForState("2 kept")
    }
    func testArchivedPhotoCanBeIdentifiedAndRecovered() {
        command("connect"); start(); card.swipeLeft(); waitForState("1 archived")
        command("stale-date"); openArchive()
        XCTAssertTrue(app.buttons["archiveItem"].firstMatch.exists)
        app.buttons["archiveItem"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["archivePreview"].firstMatch.exists)
        XCTAssertTrue(app.buttons["archiveAgain"].exists); XCTAssertTrue(app.buttons["keepArchivedOnPhone"].exists)
        app.buttons["checkCopy"].tap()
        XCTAssertTrue(app.staticTexts["Saved"].waitForExistence(timeout: 12), "Unchanged bytes must pass even when the old receipt timestamp differs")
        screenshot("06-existing-copy-rechecked")
        app.navigationBars["Photo"].buttons["Archive"].tap()
        app.buttons["verifyArchive"].tap()
        XCTAssertTrue(app.buttons["confirmRemoval"].waitForExistence(timeout: 12)); app.buttons["Cancel"].tap()
    }
    func testEditedPhotoStaysSafeAndCanBeArchivedAgain() {
        command("connect"); start(); card.swipeLeft(); waitForState("1 archived")
        command("edit"); waitForState("1 need attention")
        openArchive(); app.buttons["verifyArchive"].tap()
        XCTAssertTrue(app.staticTexts["archiveNotice"].waitForExistence(timeout: 12)); XCTAssertFalse(app.buttons["confirmRemoval"].exists)
        app.buttons["archiveItem"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["itemIssue"].waitForExistence(timeout: 5))
        app.buttons["archiveAgain"].tap()
        XCTAssertTrue(app.staticTexts["Saved"].waitForExistence(timeout: 12))
        screenshot("07-edited-photo-rearchived")
        app.navigationBars["Photo"].buttons["Archive"].tap(); confirmRemoval()
    }
    func testPendingArchiveResumesAfterRelaunch() {
        app.terminate(); app.launchArguments = ["--uitesting", "--reset-session", "--slow-archive"]; app.launch()
        command("connect"); start(); card.swipeLeft(); waitForState("1 pending")
        app.terminate(); app.launchArguments = ["--uitesting"]; app.launch()
        waitForState("1 pending"); command("connect"); waitForState("1 archived"); waitForState("0 pending")
        openArchive(); XCTAssertTrue(app.buttons["archiveItem"].firstMatch.exists)
    }
    func testCopyFailureCanBeRetriedWithoutBlockingReview() {
        command("connect"); command("read-only"); start()
        card.swipeLeft(); waitForState("1 need attention")
        XCTAssertTrue(app.staticTexts["2/3"].exists); XCTAssertFalse(app.alerts.firstMatch.exists)
        command("writable"); openArchive(); app.buttons["archiveItem"].firstMatch.tap()
        app.buttons["archiveAgain"].tap(); XCTAssertTrue(app.staticTexts["Saved"].waitForExistence(timeout: 12))
    }
    func testUndoPendingCopyDoesNotReappear() {
        app.terminate(); app.launchArguments = ["--uitesting", "--reset-session", "--slow-archive"]; app.launch()
        command("connect"); start(); card.swipeLeft(); waitForState("1 pending")
        app.buttons["undo"].tap(); waitForState("0 pending")
        XCTAssertTrue(app.staticTexts["1/3"].exists)
        let unexpected = expectation(for: NSPredicate(format: "value CONTAINS '1 archived'"), evaluatedWith: state)
        unexpected.isInverted = true; waitForExpectations(timeout: 9)
    }
    func testExistingReceiptIndexMigratesAndCanBeRechecked() {
        command("connect"); start(); card.swipeLeft(); waitForState("1 archived")
        command("legacy-index"); app.terminate(); app.launchArguments = ["--uitesting"]; app.launch()
        waitForState("1 archived"); command("connect"); openArchive()
        app.buttons["archiveItem"].firstMatch.tap(); app.buttons["checkCopy"].tap()
        XCTAssertTrue(app.staticTexts["Saved"].waitForExistence(timeout: 12))
    }
    func testOneChangedPhotoDoesNotBlockOtherVerifiedPhotos() {
        command("connect"); start(); card.swipeLeft(); waitForState("1 archived")
        card.swipeLeft(); waitForState("2 archived")
        command("edit"); waitForState("1 need attention"); openArchive()
        app.buttons["verifyArchive"].tap()
        XCTAssertTrue(app.alerts["Remove 1 verified photo?"].waitForExistence(timeout: 12))
        app.buttons["confirmRemoval"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let delete = springboard.alerts.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Delete'")).firstMatch
        if delete.waitForExistence(timeout: 8) { delete.tap() }
        let oneLeft = expectation(for: NSPredicate { _, _ in self.app.buttons.matching(identifier: "archiveItem").count == 1 }, evaluatedWith: app)
        wait(for: [oneLeft], timeout: 12)
        XCTAssertTrue(app.staticTexts["Check needed"].exists)
    }
    func testLongPhotoCheckCanBeCancelled() {
        app.terminate(); app.launchArguments = ["--uitesting", "--reset-session", "--slow-check"]; app.launch()
        command("connect"); start(); card.swipeLeft(); waitForState("1 archived")
        openArchive(); app.buttons["archiveItem"].firstMatch.tap(); app.buttons["checkCopy"].tap()
        XCTAssertTrue(app.buttons["cancelCheck"].waitForExistence(timeout: 2)); app.buttons["cancelCheck"].tap()
        XCTAssertTrue(app.buttons["keepArchivedOnPhone"].isEnabled)
        app.buttons["keepArchivedOnPhone"].tap()
        XCTAssertTrue(app.staticTexts["Archive is empty"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["confirmRemoval"].exists)
    }
    func testRemovalVerificationCanBeCancelledBeforeDeletion() {
        app.terminate(); app.launchArguments = ["--uitesting", "--reset-session", "--slow-check"]; app.launch()
        command("connect"); start(); card.swipeLeft(); waitForState("1 archived"); openArchive()
        app.buttons["verifyArchive"].tap()
        XCTAssertTrue(app.buttons["confirmRemoval"].waitForExistence(timeout: 12)); app.buttons["confirmRemoval"].tap()
        XCTAssertTrue(app.buttons["cancelCheck"].waitForExistence(timeout: 2)); app.buttons["cancelCheck"].tap()
        XCTAssertTrue(app.staticTexts["Saved"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["archiveItem"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Check needed"].exists)
        XCTAssertFalse(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Delete"].exists)
    }
    func testFirstLaunchTutorialSwipesAndStaysDismissed() {
        app.terminate(); app.launchArguments = ["--uitesting", "--show-tutorial"]; app.launch()
        XCTAssertTrue(app.staticTexts["tutorialStep"].waitForExistence(timeout: 5))
        app.swipeLeft(); XCTAssertTrue(app.staticTexts["tutorialStep"].label.hasPrefix("2 of 4"))
        app.swipeLeft(); XCTAssertTrue(app.staticTexts["tutorialStep"].label.hasPrefix("3 of 4"))
        app.buttons["tutorialNext"].tap(); app.buttons["tutorialBegin"].tap()
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments = ["--uitesting"]; app.launch()
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["tutorialSkip"].exists)
        app.buttons["showTutorial"].tap(); XCTAssertTrue(app.staticTexts["tutorialStep"].waitForExistence(timeout: 5)); app.buttons["tutorialSkip"].tap()
    }
}
