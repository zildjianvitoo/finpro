//
//  AppConfiguration+VocalRange.swift
//  finpro
//

import Foundation

// Feature defaults are computed so existing persisted configuration remains compatible.
extension AppConfiguration {
    nonisolated var keyRecommendationCount: Int { 3 }
    nonisolated var rangePenaltyBand: Double { 3 }
    nonisolated var rangePenaltySpanDivisor: Double { 4 }
    nonisolated var speakingSampleDuration: TimeInterval { 6 }
    nonisolated var minimumSpeakingVoicedDuration: TimeInterval { 2 }
    nonisolated var minimumVocalRangeSpan: Float { 3 }
}
