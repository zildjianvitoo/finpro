//
//  ModelPrewarmer.swift
//  finpro
//
//  Stages CoreML preparation so launch and the first microphone activation stay responsive.
//  Features load their own models when background preparation is unavailable.
//

import Foundation
import os
import UIKit

nonisolated struct ModelPrewarmer: Sendable {
    let htDemucs: HTDemucsStemSeparationRepository

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "finpro", category: "Prewarm")
    func preloadSeparation() {
        #if !targetEnvironment(simulator)
        Task.detached(priority: .utility) { [htDemucs] in
            let started = ContinuousClock.now
            do {
                guard await Self.isActive(), try htDemucs.preload() else { return }
                let seconds = (ContinuousClock.now - started) / .seconds(1)
                Self.log.notice("HTDemucs loaded in \(seconds, format: .fixed(precision: 2)) s")
            } catch {
                Self.log.error("HTDemucs preload failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        #endif
    }

    func warmSeparation() {
        #if !targetEnvironment(simulator)
        Task(priority: .utility) { await warmSeparationIfActive() }
        #endif
    }

    func cancelSeparationWarmup() {
        Task { await htDemucs.cancelPrewarm() }
    }

    func start() {
        VideoEncoderWarmUp.start()
        Task.detached(priority: .utility) {
            let crepe = ContinuousClock().measure { try? CrepePitchDetector.prewarm() }
            Self.log.notice("CREPE prewarm: \(crepe / .seconds(1), format: .fixed(precision: 2)) s")
            #if !targetEnvironment(simulator)
            await warmSeparationIfActive()
            #endif
        }
    }

    private func warmSeparationIfActive() async {
        do { try await htDemucs.prewarm(isActive: Self.isActive) }
        catch is CancellationError { return }
        catch { Self.log.error("HTDemucs warm-up failed: \(error.localizedDescription, privacy: .public)") }
    }

    @MainActor private static func isActive() -> Bool {
        UIApplication.shared.applicationState == .active
    }
}
