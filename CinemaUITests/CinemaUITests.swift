import XCTest

/// Driver for manual/agent-assisted UI verification. Each test performs one
/// navigation flow then pauses so a screenshot can be taken externally
/// (`xcrun simctl io <device> screenshot`) while app state is still live.
///
/// Test accounts are created directly via the Supabase REST API, not through
/// the UI onboarding flow — walking the full 12-step onboarding (with real
/// Contacts/Notifications system permission dialogs) proved slow and flaky.
/// login() signs into an already-onboarded seeded account for fast re-entry.
@MainActor
final class CinemaUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launch()
    }

    private func pause(_ seconds: TimeInterval = 60) {
        let exp = expectation(description: "pause for external screenshot")
        exp.isInverted = true
        wait(for: [exp], timeout: seconds)
    }

    private func type(_ text: String, into field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(text)
    }

    private func login() {
        let loginLink = app.buttons["Already have an account? Log in"]
        guard loginLink.waitForExistence(timeout: 5) else { return } // already-authenticated session
        loginLink.tap()
        type("qatest1@example.com", into: app.textFields["Email"])
        type("TestPass123", into: app.secureTextFields["Password"])
        let signIn = app.buttons["Sign In"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 10))
        signIn.tap()
        Thread.sleep(forTimeInterval: 1.5)
    }

    func testLists() throws {
        login()
        app.buttons["Lists"].tap()
        pause()
    }

    func testFeed() throws {
        login()
        pause()
    }

    func testDeleteCustomList() throws {
        login()
        app.buttons["Lists"].tap()

        let plusButton = app.buttons["Create List"]
        XCTAssertTrue(plusButton.waitForExistence(timeout: 5))
        plusButton.tap()

        let listName = "Delete Me \(Int(Date().timeIntervalSince1970))"
        let nameField = app.textFields["Funny Movies"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(listName)
        app.buttons["Create"].tap()

        let pill = app.buttons[listName]
        XCTAssertTrue(pill.waitForExistence(timeout: 10))
        pill.press(forDuration: 1.0)

        let deleteListMenuItem = app.buttons["Delete List"]
        XCTAssertTrue(deleteListMenuItem.waitForExistence(timeout: 5))
        deleteListMenuItem.tap()

        let deleteButton = app.alerts.buttons["Delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        deleteButton.tap()

        let goneExpectation = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: pill)
        wait(for: [goneExpectation], timeout: 5)
        pause()
    }

    /// One-off cleanup for stray "Delete Me ..." lists left behind by earlier
    /// failed runs of testDeleteCustomList while that flow was being fixed.
    func testCleanupStrayLists() throws {
        login()
        app.buttons["Lists"].tap()

        while true {
            let strayPill = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Delete Me '")).firstMatch
            guard strayPill.waitForExistence(timeout: 3) else { break }
            strayPill.press(forDuration: 1.0)
            let menuItem = app.buttons["Delete List"]
            guard menuItem.waitForExistence(timeout: 3) else { break }
            menuItem.tap()
            let confirm = app.alerts.buttons["Delete"]
            guard confirm.waitForExistence(timeout: 3) else { break }
            confirm.tap()
            Thread.sleep(forTimeInterval: 1.0)
        }
    }

    func testScorePreviewToggle() throws {
        login()
        app.buttons["Profile"].tap()

        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()

        let toggle = app.switches["Rankings Score Preview Toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()

        app.buttons["Done"].tap()
        app.buttons["Lists"].tap()
        pause()
    }

    func testSearchMovieOnly() throws {
        login()
        app.buttons["Search"].tap()

        let searchField = app.textFields["Search films..."]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("Minions")
        pause()
    }

    func testClearButtonDismissesKeyboard() throws {
        login()
        app.buttons["Search"].tap()

        let searchField = app.textFields["Search films..."]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("Minion")

        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))

        let clearButton = app.buttons["xmark.circle.fill"]
        XCTAssertTrue(clearButton.waitForExistence(timeout: 5))
        clearButton.tap()

        let keyboardGone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.keyboards.firstMatch)
        wait(for: [keyboardGone], timeout: 5)
        pause()
    }

    func testSearchGenreChipFiltersTypedResults() throws {
        login()
        app.buttons["Search"].tap()

        let searchField = app.textFields["Search films..."]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("Minion")

        let comedyChip = app.buttons["Comedy"]
        XCTAssertTrue(comedyChip.waitForExistence(timeout: 5))
        comedyChip.tap()
        pause()
    }

    func testSearchTapOpensListPickerAndAutoDismisses() throws {
        login()
        app.buttons["Search"].tap()

        let searchField = app.textFields["Search films..."]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("Minion")

        let firstQuickActions = app.buttons["Quick Actions"].firstMatch
        XCTAssertTrue(firstQuickActions.waitForExistence(timeout: 5))
        firstQuickActions.tap()

        let addToListMenuItem = app.buttons["Add to List"]
        XCTAssertTrue(addToListMenuItem.waitForExistence(timeout: 5))
        addToListMenuItem.tap()

        let watchlistRow = app.buttons["addToListSheet.row.Watchlist"]
        XCTAssertTrue(watchlistRow.waitForExistence(timeout: 5))
        watchlistRow.tap()

        // No Done button anymore — tapping a row should toggle it and close the sheet on its own.
        let goneExpectation = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: watchlistRow)
        wait(for: [goneExpectation], timeout: 5)
        pause()
    }

    func testFindPeopleFromProfile() throws {
        login()
        app.buttons["Profile"].tap()

        let findPeople = app.buttons["Find People"]
        XCTAssertTrue(findPeople.waitForExistence(timeout: 5))
        findPeople.tap()

        let searchField = app.textFields["Search by username..."]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.typeText("a")
        pause()
    }

    func testRetappingRankedItemReopensRanking() throws {
        login()
        app.buttons["Search"].tap()

        let searchField = app.textFields["Search films..."]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("Minion")

        let firstQuickActions = app.buttons["Quick Actions"].firstMatch
        XCTAssertTrue(firstQuickActions.waitForExistence(timeout: 5))
        firstQuickActions.tap()

        let reRank = app.buttons["Re-Rank"]
        XCTAssertTrue(reRank.waitForExistence(timeout: 5))
        reRank.tap()
        pause()
    }

    func testMovieDetailShowsVoteCount() throws {
        login()
        app.buttons["Search"].tap()

        let searchField = app.textFields["Search films..."]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("Minions")

        let firstPoster = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'searchGridTile.poster.'")).firstMatch
        XCTAssertTrue(firstPoster.waitForExistence(timeout: 5))
        firstPoster.tap()
        pause()
    }

    func testSwipeCommitsPick() throws {
        XCTAssertTrue(app.staticTexts["0"].waitForExistence(timeout: 5))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(app.staticTexts["1"].waitForExistence(timeout: 5))
        pause()
    }
}
