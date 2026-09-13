//
//  transormaUITests.swift
//  transormaUITests
//
//  Created by Tyler Cross on 8/6/25.
//

import XCTest

final class transormaUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    @MainActor
    func testProtectionRequiresExplicitOptIn() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Less marketing. More mail."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Protection is paused"].exists)
        let toggle = app.descendants(matching: .any).matching(identifier: "protection-toggle").firstMatch
        XCTAssertTrue(toggle.exists)
        toggle.click()
        XCTAssertTrue(app.staticTexts["Protection enabled · waiting for incoming mail"].waitForExistence(timeout: 3))
        toggle.click()
        XCTAssertTrue(app.staticTexts["Protection is paused"].exists)
    }

    @MainActor
    func testPrivacyIsAccessibleBeforeEnablingProtection() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let privacy = app.outlines.staticTexts["Privacy"]
        XCTAssertTrue(privacy.waitForExistence(timeout: 10))
        privacy.click()
        XCTAssertTrue(app.staticTexts["Your mail stays yours."].waitForExistence(timeout: 3))
    }
}
