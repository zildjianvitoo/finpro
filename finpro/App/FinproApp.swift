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
    }

    var body: some Scene {
        WindowGroup {
            Group {
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
            .task {
                // Defer TipKit store setup and heavy CoreML/VideoToolbox prewarm until after the
                // first SwiftUI frame paints, avoiding a long white launch screen on fresh installs.
                try? Tips.configure()
                flow.startBackgroundWarmUp()
            }
        }
        // Leaving the app copies the newest messages right away (it may not come back).
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { AppEventLog.shared.flush() }
        }
    }
}
