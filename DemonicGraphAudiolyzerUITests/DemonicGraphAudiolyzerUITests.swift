//
//  DemonicGraphAudiolyzerUITests.swift
//  DemonicGraphAudiolyzerUITests
//
//  Created by David Martens on 13.10.26.
//

import XCTest

final class DemonicGraphAudiolyzerUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
        app = nil
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// Waits until the transport status shows `text`. Returns false on timeout.
    private func waitForStatus(_ text: String, timeout: TimeInterval = 10) -> Bool {
        let status = element("transportStatus")
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: status)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Formel eingeben → Graph anzeigen → abspielen → pausieren → stoppen.
    @MainActor
    func testEnterFormulaShowGraphPlayPauseStop() throws {
        app.launch()

        let field = app.textFields["formulaField"]
        XCTAssertTrue(field.waitForExistence(timeout: 15), "Formelfeld fehlt")

        let clear = app.buttons["clearFormula"]
        if clear.exists { clear.tap() }
        field.tap()
        field.typeText("sin(x)*2")
        let done = app.buttons["keyboardDone"]
        if done.waitForExistence(timeout: 3) {
            done.tap()
        }

        // Graph shows the new formula.
        let graph = element("graphCanvas")
        XCTAssertTrue(graph.waitForExistence(timeout: 5), "Graph fehlt")
        XCTAssertTrue(graph.label.contains("sin(x)*2"), "Graph zeigt nicht die eingegebene Formel: \(graph.label)")
        XCTAssertTrue(element("formulaStatus").exists, "Formel sollte gültig sein")
        XCTAssertTrue(waitForStatus("Bereit"))

        // Play
        let play = app.buttons["playButton"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()
        let playing = waitForStatus("Wiedergabe", timeout: 15)
        if !playing, element("transportStatus").label.contains("Fehler") {
            throw XCTSkip("Keine Audioausgabe in dieser Umgebung verfügbar")
        }
        XCTAssertTrue(playing, "Wiedergabe startet nicht")

        // Pause
        let pause = app.buttons["pauseButton"]
        XCTAssertTrue(pause.isEnabled)
        pause.tap()
        XCTAssertTrue(waitForStatus("Pausiert"), "Pausieren funktioniert nicht")

        // Stop
        app.buttons["stopButton"].tap()
        XCTAssertTrue(waitForStatus("Bereit"), "Stoppen funktioniert nicht")
    }

    @MainActor
    func testInvalidFormulaShowsErrorAndDisablesPlayback() throws {
        app.launch()
        let field = app.textFields["formulaField"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        let clear = app.buttons["clearFormula"]
        if clear.exists { clear.tap() }
        field.tap()
        field.typeText("sin(x")
        if app.buttons["keyboardDone"].waitForExistence(timeout: 3) {
            app.buttons["keyboardDone"].tap()
        }
        XCTAssertTrue(element("formulaError").waitForExistence(timeout: 5), "Fehlermeldung fehlt")
        XCTAssertTrue(waitForStatus("Formel ungültig"))
        XCTAssertFalse(app.buttons["playButton"].isEnabled)
    }

    @MainActor
    func testLandscapeShowsGraphAndControls() throws {
        app.launch()
        XCTAssertTrue(app.textFields["formulaField"].waitForExistence(timeout: 15))
        XCUIDevice.shared.orientation = .landscapeLeft
        let graph = element("graphCanvas")
        XCTAssertTrue(graph.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["playButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(graph.frame.width > graph.frame.height * 0.8, "Graph nutzt im Querformat die Breite")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(graph.waitForExistence(timeout: 5))
    }

    @MainActor
    func testMainAreasAreReachable() throws {
        app.launch()
        XCTAssertTrue(app.buttons["tab-presets"].waitForExistence(timeout: 15))
        app.buttons["tab-presets"].tap()
        XCTAssertTrue(app.buttons["loadPreset-Stufen"].waitForExistence(timeout: 5))
        app.buttons["loadPreset-Stufen"].tap()
        XCTAssertTrue(element("graphCanvas").waitForExistence(timeout: 5))
        XCTAssertTrue(element("graphCanvas").label.contains("floor(x)"))
        app.buttons["tab-settings"].tap()
        XCTAssertTrue(app.staticTexts["Klangmodi erklärt"].waitForExistence(timeout: 5) || element("Klangmodi erklärt").exists)
    }
}
