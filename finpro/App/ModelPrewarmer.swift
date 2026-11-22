//
//  ModelPrewarmer.swift
//  finpro
//
//  Loads the CoreML models in the background when the app opens, so Preparation (htdemucs,
//  CREPE guide) and the vocal range test / recording (live CREPE) don't wait for them.
//  Failures are ignored here: each feature loads (and reports) its model again when used.
//  The log line counts prewarms since install, to see whether the slow first htdemucs run (the
//  GPU compile, ~25 s right after install) comes back on later launches.
//

import Foundation
import os

nonisolated struct ModelPrewarmer: Sendable {
    let htDemucs: HTDemucsStemSeparationRepository

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "finpro", category: "Prewarm")
    /// UserDefaults keys (cleared on uninstall): prewarms started and finished since install.
    private static let startedKey = "prewarm.started"
    private static let finishedKey = "prewarm.finished"

    func start() {
        // Not a model, but the same idea: the first video encoder start after an install is slow.
        VideoEncoderWarmUp.start()
        Task.detached(priority: .utility) { [htDemucs] in
            let defaults = UserDefaults.standard
            let run = defaults.integer(forKey: Self.startedKey) + 1
            let finishedBefore = defaults.integer(forKey: Self.finishedKey)
            defaults.set(run, forKey: Self.startedKey)
            let clock = ContinuousClock()
            // CREPE first: it is small and the vocal range test may need it right away.
            let crepe = clock.measure { try? CrepePitchDetector.prewarm() }
            let separation = clock.measure { try? htDemucs.prewarm() }
            defaults.set(finishedBefore + 1, forKey: Self.finishedKey)
            Self.log.notice("""
                prewarm: CREPE \(crepe / .seconds(1), format: .fixed(precision: 2)) s, \
                htdemucs \(separation / .seconds(1), format: .fixed(precision: 2)) s \
                (prewarm \(run) since install, \(finishedBefore) finished before)
                """)
        }
    }
}
