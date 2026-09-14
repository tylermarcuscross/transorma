import XCTest

final class TransormaUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testProtectionRequiresExplicitOptIn() throws {
        let app = launchApp()
        XCTAssertTrue(app.outlines.staticTexts["Settings"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.textFields["Email address or domain"].exists)
        XCTAssertFalse(app.staticTexts["Keep list"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "open-mail-settings").firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Protection is paused"].exists)
        let loginToggle = app.descendants(matching: .any).matching(identifier: "login-toggle").firstMatch
        XCTAssertTrue(loginToggle.exists)
        XCTAssertFalse(loginToggle.isEnabled)
        XCTAssertTrue(app.staticTexts["Login launch is disabled in this development build."].exists)
        let toggle = app.descendants(matching: .any).matching(identifier: "protection-toggle").firstMatch
        XCTAssertTrue(toggle.exists)
        XCTAssertTrue(app.staticTexts["Activate Transorma"].exists)
        toggle.click()
        XCTAssertTrue(app.staticTexts["Protection enabled · waiting for Mail"].waitForExistence(timeout: 3))
        toggle.click()
        XCTAssertTrue(app.staticTexts["Protection is paused"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Settings"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testNavigationContainsSettingsAndActivity() throws {
        let app = launchApp()
        XCTAssertTrue(app.outlines.staticTexts["Settings"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.outlines.staticTexts.count, 2)
        app.outlines.staticTexts["Activity"].click()
        XCTAssertTrue(app.staticTexts["No activity yet"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.textFields["Email address or domain"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Activity"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testMenuBarNavigationShortcutsAndQuit() throws {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["Protection is paused"].waitForExistence(timeout: 10))
        app.descendants(matching: .any).matching(identifier: "protection-toggle").firstMatch.click()
        app.outlines.staticTexts["Activity"].click()

        let menuBarItem = app.descendants(matching: .any).matching(identifier: "transorma-menu-bar").firstMatch
        XCTAssertTrue(menuBarItem.waitForExistence(timeout: 3))
        menuBarItem.click()
        XCTAssertTrue(menuBarItem.menuItems["Settings…"].exists)
        XCTAssertTrue(menuBarItem.menuItems["Quit"].exists)
        XCTAssertFalse(menuBarItem.menuItems["Automatic Protection"].exists)
        XCTAssertFalse(menuBarItem.menuItems["Quit Transorma"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Menu bar"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        menuBarItem.menuItems["Open Transorma"].click()
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(app.staticTexts["No activity yet"].exists)
        menuBarItem.click()
        menuBarItem.menuItems["Settings…"].click()
        XCTAssertTrue(app.staticTexts["Protection enabled · waiting for Mail"].waitForExistence(timeout: 3))

        app.outlines.staticTexts["Activity"].click()
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Protection enabled · waiting for Mail"].waitForExistence(timeout: 3))
        app.outlines.staticTexts["Activity"].click()
        app.windows.firstMatch.buttons[XCUIIdentifierCloseWindow].click()
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["No activity yet"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.windows.count, 1)

        app.windows.firstMatch.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertEqual(app.windows.count, 0)
        menuBarItem.click()
        menuBarItem.menuItems["Settings…"].click()
        XCTAssertTrue(app.staticTexts["Protection enabled · waiting for Mail"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.windows.count, 1)
        menuBarItem.click()
        menuBarItem.menuItems["Quit"].click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
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
        menuBarItem.menuItems["Open Transorma"].click()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        return app
    }
}
