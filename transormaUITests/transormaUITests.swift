//
//  transormaUITests.swift
//  transormaUITests
//
//  Created by Tyler Cross on 8/6/25.
//

import XCTest

final class TransormaUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
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
