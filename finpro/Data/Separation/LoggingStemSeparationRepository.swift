//
//  LoggingStemSeparationRepository.swift
//  finpro
//
//  Wraps a separation method and logs its time, memory footprint and errors (Debug builds), so
//  device tests can read them from the console (subsystem = bundle id, category "Separation").
//

import Foundation
import os

nonisolated struct LoggingStemSeparationRepository: StemSeparationRepository, LeadInStemSeparation, StemPreseparation {
    let name: String
    let wrapped: any StemSeparationRepository

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "finpro", category: "Separation")

    func preseparate(audioURL: URL, trimRange: ClosedRange<TimeInterval>, leadInDuration: TimeInterval) async {
        guard let preseparator = wrapped as? any StemPreseparation else { return }
        await preseparator.preseparate(audioURL: audioURL, trimRange: trimRange, leadInDuration: leadInDuration)
    }

    func separateStems(from audioURL: URL, trimRange: ClosedRange<TimeInterval>) async throws -> SeparatedStems {
        try await logged(duration: trimRange.upperBound - trimRange.lowerBound) {
            try await wrapped.separateStems(from: audioURL, trimRange: trimRange)
        }
    }

    func separateStems(from audioURL: URL, trimRange: ClosedRange<TimeInterval>,
                       leadInDuration: TimeInterval) async throws -> (stems: SeparatedStems, leadIn: SeparatedStems?) {
        if let combined = wrapped as? any LeadInStemSeparation {
            return try await logged(duration: trimRange.upperBound - trimRange.lowerBound + max(0, leadInDuration)) {
                try await combined.separateStems(from: audioURL, trimRange: trimRange, leadInDuration: leadInDuration)
            }
        }
        let stems = try await separateStems(from: audioURL, trimRange: trimRange)
        guard leadInDuration > 0 else { return (stems, nil) }
        let leadIn = try? await separateStems(from: audioURL, trimRange: (trimRange.lowerBound - leadInDuration)...trimRange.lowerBound)
        return (stems, leadIn)
    }

    private func logged<T>(duration: TimeInterval, work: () async throws -> T) async throws -> T {
        #if DEBUG
        let before = MemoryFootprint.snapshot()
        let clock = ContinuousClock()
        let started = clock.now
        do {
            let result = try await work()
            let after = MemoryFootprint.snapshot()
            let seconds = (clock.now - started) / .seconds(1)
            Self.log.notice("""
                \(name, privacy: .public): \(duration, format: .fixed(precision: 1)) s \
                in \(seconds, format: .fixed(precision: 2)) s | footprint \(before.currentMB, format: .fixed(precision: 0)) → \
                \(after.currentMB, format: .fixed(precision: 0)) MB, peak \(before.peakMB, format: .fixed(precision: 0)) → \
                \(after.peakMB, format: .fixed(precision: 0)) MB, available before \(before.availableMB, format: .fixed(precision: 0)) MB
                """)
            return result
        } catch {
            Self.log.error("\(name, privacy: .public) failed after \((clock.now - started) / .seconds(1), format: .fixed(precision: 2)) s: \(String(describing: error), privacy: .public)")
            throw error
        }
        #else
        return try await work()
        #endif
    }
}
