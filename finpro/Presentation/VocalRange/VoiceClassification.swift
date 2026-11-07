//
//  VoiceClassification.swift
//  finpro
//
//  Voice types and comfort zone calculation for display.
//

import Foundation

enum VoiceClassification {
    static func classify(range: VocalRange, isFemale: Bool) -> (name: String, comfortLowMIDI: Float, comfortHighMIDI: Float) {
        // Classify on the same whole notes the screen shows, so a range labelled C3-G4 always
        // gets the same voice type however many cents above or below G4 it was sung.
        let low = range.lowestMIDI.rounded()
        let high = range.highestMIDI.rounded()

        let comfortLow = min(high - 4, low + 3)
        let comfortHigh = max(comfortLow + 4, high - 3)

        if isFemale {
            if high >= 74 {
                return ("SOPRANO", comfortLow, comfortHigh)
            } else if high >= 67 {
                return ("MEZZO-SOPRANO", comfortLow, comfortHigh)
            } else {
                return ("CONTRALTO", comfortLow, comfortHigh)
            }
        } else {
            if high >= 67 {
                return ("TENOR", comfortLow, comfortHigh)
            } else if high >= 59 {
                return ("BARITONE", comfortLow, comfortHigh)
            } else {
                return ("BASS", comfortLow, comfortHigh)
            }
        }
    }
}
