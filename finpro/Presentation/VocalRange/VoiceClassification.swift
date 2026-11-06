//
//  VoiceClassification.swift
//  finpro
//
//  Voice types and comfort zone calculation for display.
//

import Foundation

enum VoiceClassification {
    static func classify(range: VocalRange, isFemale: Bool) -> (name: String, comfortLowMIDI: Float, comfortHighMIDI: Float) {
        let low = range.lowestMIDI
        let high = range.highestMIDI

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
