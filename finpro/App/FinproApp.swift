//
//  FinproApp.swift
//  finpro
//
//  Created by Zildjian Vito  on 31/10/26.
//

import os
import SwiftUI
import TipKit

@main
struct FinproApp: App {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "finpro", category: "Launch")
    private let launchedAt: ContinuousClock.Instant
    @State private var flow: AppFlow
    @State private var loggedFirstFrame = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let start = ContinuousClock.now
        launchedAt = start
        // Before anything else logs, so the launch marker comes first in the file.
        AppEventLog.shared.start()
        _flow = State(initialValue: AppFlow(container: .makeDefault()))
        let initElapsed = (ContinuousClock.now - start) / .seconds(1)
        Self.log.notice("app init finished in \(initElapsed, format: .fixed(precision: 3)) s")
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
            .onAppear {
                guard !loggedFirstFrame else { return }
                loggedFirstFrame = true
                let elapsed = (ContinuousClock.now - launchedAt) / .seconds(1)
                Self.log.notice("first frame appeared in \(elapsed, format: .fixed(precision: 3)) s")
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
