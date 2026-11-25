//
//  PreviewPitchPoint.swift
//  finpro
//

import Foundation

/// A sample of the displayed voice dot, on the song timeline of a kept take.
nonisolated struct PreviewPitchPoint: Codable, Sendable {
    let midi: Float
    let songTime: TimeInterval

    /// The last voiced sample at or before the playhead, including when seeking backward.
    static func last(at time: TimeInterval, in points: [Self]) -> Self? {
        var low = 0
        var high = points.count
        while low < high {
            let middle = low + (high - low) / 2
            if points[middle].songTime <= time { low = middle + 1 }
            else { high = middle }
        }
        guard low > 0, time - points[low - 1].songTime < VoiceDotFilter.phraseGap else { return nil }
        return points[low - 1]
    }
}
