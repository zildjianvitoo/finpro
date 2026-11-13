//
//  VocalPitchRuler.swift
//  finpro
//

import SwiftUI

/// Consecutive chromatic notes scroll toward the center as the microphone pitch changes.
struct VocalPitchRuler: View {
    let midi: Float?
    let referenceMIDI: Float
    @State private var lastHeardMIDI: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var position: LivePitchPositionUseCase.Position? { LivePitchPositionUseCase().execute(midi: midi) }
    private var scaleCenter: Double {
        position?.noteMIDI ?? lastHeardMIDI ?? (referenceMIDI.isFinite ? min(127, max(0, Double(referenceMIDI))) : 57)
    }
    private var spokenDescription: String {
        guard let position else { return "No voice detected" }
        return "\(PitchMath.noteName(midi: position.nearestNote)), \(Int(PitchMath.frequency(fromMIDI: position.midi))) hertz"
    }
    var body: some View {
        CurvedPitchDial(value: position?.noteMIDI ?? scaleCenter, center: scaleCenter, bounds: 0...127,
                        hasSignal: position != nil, highlightsPitch: true,
                        label: { PitchMath.noteName(midi: Int($0.rounded())) })
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: midi)
            .onChange(of: midi, initial: true) { _, _ in
                if let position { lastHeardMIDI = position.noteMIDI }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Detected pitch, chromatic note scale")
            .accessibilityValue(spokenDescription)
    }
}
