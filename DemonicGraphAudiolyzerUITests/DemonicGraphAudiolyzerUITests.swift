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

    /// Keeps a screenshot in the test report (design review of all main views).
    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Waits until the transport status shows `text`. Returns false on timeout.
    private func waitForStatus(_ text: String, timeout: TimeInterval = 10) -> Bool {
        let status = element("transportStatus")
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if status.exists, status.label.contains(text) { return true }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        diagnose("Status '\(text)' nicht erreicht, aktuell: '\(status.exists ? status.label : "fehlt")'")
        return false
    }

    /// Scrolls the main column (dragging in the right-hand margin, never on the graph) until
    /// `element` is hittable and not covered by the tab bar.
    private func bringIntoView(_ element: XCUIElement) {
        let tabBar = app.buttons["tab-graph"]
        for _ in 0..<6 {
            let coveredByTabBar = tabBar.exists && element.frame.maxY > tabBar.frame.minY - 8
            if element.isHittable && !coveredByTabBar { return }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.985, dy: 0.7))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -220)))
        }
    }

    /// Writes the accessibility hierarchy to the log and the test report.
    private func diagnose(_ reason: String) {
        let hierarchy = app.debugDescription
        print("=== UI-DIAGNOSE: \(reason) ===\n\(hierarchy)\n=== UI-DIAGNOSE ENDE ===")
        let attachment = XCTAttachment(string: hierarchy)
        attachment.name = "Hierarchie – \(reason)"
        attachment.lifetime = .keepAlways
        add(attachment)
        screenshot("Diagnose – \(reason)")
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
        screenshot("01 Graph angezeigt")

        // Repeat on, so the pass is still running when the (slow) UI automation pauses it.
        let loop = app.buttons["loopButton"]
        bringIntoView(loop)
        loop.tap()
        XCTAssertEqual(loop.value as? String, "ein")

        // Play
        let play = app.buttons["playButton"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        bringIntoView(play)
        play.tap()
        let playing = waitForStatus("Wiedergabe", timeout: 15)
        if !playing, element("transportStatus").label.contains("Fehler") {
            throw XCTSkip("Keine Audioausgabe in dieser Umgebung verfügbar")
        }
        XCTAssertTrue(playing, "Wiedergabe startet nicht")
        Thread.sleep(forTimeInterval: 2.5)
        screenshot("02 Wiedergabe")

        // Pause
        let pause = app.buttons["pauseButton"]
        XCTAssertTrue(pause.isEnabled)
        bringIntoView(pause)
        pause.tap()
        XCTAssertTrue(waitForStatus("Pausiert"), "Pausieren funktioniert nicht")
        screenshot("03 Pausiert")

        // Stop
        bringIntoView(app.buttons["stopButton"])
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
        screenshot("04 Formelfehler")
        XCTAssertFalse(app.buttons["playButton"].isEnabled)
    }

    @MainActor
    func testLandscapeShowsGraphAndControls() throws {
        app.launch()
        XCTAssertTrue(app.textFields["formulaField"].waitForExistence(timeout: 15))
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 1.5)
        let graph = element("graphCanvas")
        XCTAssertTrue(graph.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["playButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(graph.frame.width > graph.frame.height * 0.8, "Graph nutzt im Querformat die Breite")
        screenshot("05 Querformat")
        if app.buttons["fullscreenButton"].exists {
            app.buttons["fullscreenButton"].tap()
            Thread.sleep(forTimeInterval: 1)
            screenshot("06 Vollbild quer")
            if app.buttons["closeFullscreen"].waitForExistence(timeout: 3) {
                app.buttons["closeFullscreen"].tap()
            }
        }
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(graph.waitForExistence(timeout: 5))
    }

    @MainActor
    func testMainAreasAreReachable() throws {
        app.launch()
        XCTAssertTrue(app.buttons["tab-presets"].waitForExistence(timeout: 15))
        app.buttons["tab-presets"].tap()
        XCTAssertTrue(app.buttons["loadPreset-Stufen"].waitForExistence(timeout: 5))
        screenshot("07 Presets")
        app.buttons["loadPreset-Stufen"].tap()
        XCTAssertTrue(element("graphCanvas").waitForExistence(timeout: 5))
        XCTAssertTrue(element("graphCanvas").label.contains("floor(x)"))
        screenshot("08 Preset Stufen geladen")
        app.buttons["tab-settings"].tap()
        XCTAssertTrue(app.staticTexts["Klangmodi erklärt"].waitForExistence(timeout: 5) || element("Klangmodi erklärt").exists)
        screenshot("09 Einstellungen")
        app.buttons["tab-graph"].tap()
        let export = app.buttons["exportButton"]
        if export.waitForExistence(timeout: 5) {
            export.tap()
            XCTAssertTrue(app.buttons["startExport"].waitForExistence(timeout: 5))
            screenshot("10 Exportdialog")
        }
    }
}
