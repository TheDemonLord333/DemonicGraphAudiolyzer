//
//  DemonicGraphAudiolyzerUITestsLaunchTests.swift
//  DemonicGraphAudiolyzerUITests
//
//  Created by David Martens on 13.10.26.
//

import XCTest

final class DemonicGraphAudiolyzerUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.textFields["formulaField"].waitForExistence(timeout: 15))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Startbildschirm Graph & Klang"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
