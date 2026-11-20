//
//  LivePitchPositionUseCase.swift
//  finpro
//

import Foundation

/// Chromatic note location. The whole scale follows continuous detected MIDI, not a fixed range fraction.
nonisolated struct LivePitchPositionUseCase: Sendable {
    struct Position: Equatable, Sendable {
        let midi: Double
        var nearestNote: Int { Int(midi.rounded()) }
        /// Display anchors to the same chromatic note used by its label.
        var noteMIDI: Double { Double(nearestNote) }
        var centsFromNote: Double { (midi - Double(nearestNote)) * 100 }
        func offset(of note: Int) -> Double { Double(note) - midi }
    }
    func execute(midi: Float?) -> Position? {
        guard let midi, midi.isFinite, (0...127).contains(midi) else { return nil }
        return Position(midi: Double(midi))
    }
    func execute(frequency: Double?) -> Position? {
        guard let frequency, frequency.isFinite, frequency > 0 else { return nil }
        return execute(midi: Float(69 + 12 * log2(frequency / 440)))
    }
}
