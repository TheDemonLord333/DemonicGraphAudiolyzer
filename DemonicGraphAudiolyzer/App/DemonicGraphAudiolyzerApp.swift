//
//  DemonicGraphAudiolyzerApp.swift
//  DemonicGraphAudiolyzer
//
//  Created by David Martens on 13.10.26.
//

import SwiftData
import SwiftUI
import UIKit

@main
struct DemonicGraphAudiolyzerApp: App {
    @State private var model: AudiolyzerModel
    private let container: ModelContainer

    /// Launch argument used by the UI tests: in-memory store, no restored session.
    static let uiTestingArgument = "-ui-testing"

    init() {
        let isUITesting = ProcessInfo.processInfo.arguments.contains(Self.uiTestingArgument)
        container = PersistenceController.makeContainer(inMemory: isUITesting)
        let sessionStore = SessionStateStore(defaults: .standard, isEnabled: !isUITesting)
        _model = State(initialValue: AudiolyzerModel(sessionStore: sessionStore))
        DemonAppearance.configure()
        if isUITesting {
            UIView.setAnimationsEnabled(false)
        }
        Task.detached(priority: .background) {
            ExportStorage.removeStaleExports()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(DemonTheme.green)
        }
        .modelContainer(container)
    }
}
