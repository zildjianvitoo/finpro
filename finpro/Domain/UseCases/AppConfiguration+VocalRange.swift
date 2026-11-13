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
    nonisolated var minimumVocalRangeSpan: Float { 3 }
}
