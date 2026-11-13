//
//  AppConfiguration+VocalRange.swift
//  finpro
//

import Foundation

// Feature defaults are computed so existing persisted configuration remains compatible.
extension AppConfiguration {
    nonisolated var readingWordsPerSecond: Double { 2.5 }
    nonisolated var vocalWaveformFrameCount: Int { 25 }
    nonisolated var vocalWaveformCeilingDBFS: Float { -12 }
    nonisolated var vocalRangeHoldDuration: TimeInterval { 1 }
    nonisolated var keyRecommendationCount: Int { 3 }
    nonisolated var rangePenaltyExtremesWeight: Double { 0.5 }
    nonisolated var rangePenaltyBand: Double { 3 }
    nonisolated var rangePenaltySpanDivisor: Double { 4 }
    nonisolated var speakingSampleDuration: TimeInterval { 6 }
    nonisolated var minimumSpeakingVoicedDuration: TimeInterval { 2 }
    /// Warm-up: a quiet moment this short (between words, on a consonant) still counts as reading.
    nonisolated var speechPauseTolerance: TimeInterval { 0.5 }
    nonisolated var minimumVocalRangeSpan: Float { 3 }
    /// Key fit: this share of the melody's sung time at each pitch extreme (a short ad-lib, a
    /// mistracked note) is left out of the "fits your range" check. It still counts in the scores.
    nonisolated var keyFitOutlierFraction: Double { 0.05 }
}
