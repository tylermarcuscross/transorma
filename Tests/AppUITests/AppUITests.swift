import XCTest

final class TransormaUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testProtectionRequiresExplicitOptIn() throws {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["Less marketing. More mail."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Protection is paused"].exists)
        let toggle = app.descendants(matching: .any).matching(identifier: "protection-toggle").firstMatch
        XCTAssertTrue(toggle.exists)
        toggle.click()
        XCTAssertTrue(app.staticTexts["Protection enabled · waiting for incoming mail"].waitForExistence(timeout: 3))
        toggle.click()
        XCTAssertTrue(app.staticTexts["Protection is paused"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Protection overview"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testKeepListRecoversAfterInvalidInput() throws {
        let app = launchApp()
        let keepList = app.outlines.staticTexts["Keep list"]
        XCTAssertTrue(keepList.waitForExistence(timeout: 10))
        keepList.click()
        let entry = app.textFields["Email address or domain"]
        XCTAssertTrue(entry.waitForExistence(timeout: 3))
        entry.click()
        entry.typeText("invalid address")
        app.outlines.staticTexts["Privacy"].click()
        keepList.click()
        XCTAssertEqual(entry.value as? String, "invalid address")
        app.buttons["Add"].click()
        XCTAssertTrue(
            app.staticTexts[
                "Enter an email address or domain, such as news@example.com or example.com."
            ].exists)
        XCTAssertEqual(entry.value as? String, "invalid address")
        entry.click()
        entry.typeKey("a", modifierFlags: .command)
        entry.typeText("example.com")
        app.buttons["Add"].click()
        XCTAssertTrue(app.staticTexts["example.com"].exists)
        XCTAssertEqual(entry.value as? String, "")
        app.buttons["Remove"].click()
        XCTAssertFalse(app.staticTexts["example.com"].exists)
    }

    @MainActor
    func testPrivacyIsAccessibleBeforeEnablingProtection() throws {
        let app = launchApp()
        let privacy = app.outlines.staticTexts["Privacy"]
        XCTAssertTrue(privacy.waitForExistence(timeout: 10))
        privacy.click()
        XCTAssertTrue(app.staticTexts["Your mail stays yours."].waitForExistence(timeout: 3))
    }

    @MainActor
    func testMenuBarSharesProtectionStateAndReopensWindow() throws {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["Protection is paused"].waitForExistence(timeout: 10))

        let menuBarItem = app.descendants(matching: .any).matching(identifier: "transorma-menu-bar").firstMatch
        XCTAssertTrue(menuBarItem.waitForExistence(timeout: 3))
        menuBarItem.click()
        app.menuItems["Open Transorma"].click()
        XCTAssertEqual(app.windows.count, 1)
        menuBarItem.click()
        app.menuItems["Automatic Protection"].click()
        XCTAssertTrue(app.staticTexts["Protection enabled · waiting for incoming mail"].waitForExistence(timeout: 3))

        app.windows.firstMatch.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertEqual(app.windows.count, 0)
        menuBarItem.click()
        app.menuItems["Open Transorma"].click()
        XCTAssertTrue(app.staticTexts["Protection enabled · waiting for incoming mail"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.windows.count, 1)
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        // XCTest can launch a menu bar app without the normal event that opens its dashboard.
        let menuBarItem = app.descendants(matching: .any).matching(identifier: "transorma-menu-bar").firstMatch
        XCTAssertTrue(menuBarItem.waitForExistence(timeout: 5))
        menuBarItem.click()
        app.menuItems["Open Transorma"].click()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        return app
    }
}
