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
        let field = app.textFields["formulaField"]
        if !field.waitForExistence(timeout: 20) {
            print("=== UI-DIAGNOSE: Launch ohne Formelfeld ===\n\(app.debugDescription)\n=== UI-DIAGNOSE ENDE ===")
        }
        XCTAssertTrue(app.descendants(matching: .any)["graphCanvas"].waitForExistence(timeout: 5) || field.exists,
                      "Startbildschirm zeigt weder Formelfeld noch Graph")

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Startbildschirm Graph & Klang"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
