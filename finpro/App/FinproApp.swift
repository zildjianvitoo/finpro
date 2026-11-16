//
//  FinproApp.swift
//  finpro
//
//  Created by Zildjian Vito  on 31/10/26.
//

import SwiftUI
import TipKit

@main
struct FinproApp: App {
    @State private var flow: AppFlow
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Before anything else logs, so the launch marker comes first in the file.
        AppEventLog.shared.start()
        _flow = State(initialValue: AppFlow(container: .makeDefault()))
        // TipKit stores which tips were shown or dismissed; a failure only means no tips.
        try? Tips.configure()
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if DebugOptions.launchScreen == "designSystem" {
                DesignSystemGalleryView()
            } else {
                RootView(flow: flow)
            }
            #else
            RootView(flow: flow)
            #endif
        }
        // Leaving the app copies the newest messages right away (it may not come back).
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { AppEventLog.shared.flush() }
        }
    }
}
