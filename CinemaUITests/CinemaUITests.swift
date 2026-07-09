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
        app.buttons["Numbered List"].tap()
        pause()
    }
}
