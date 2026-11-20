//
//  PreviewEnvelope.swift
//  finpro
//
//  Volume shape of one composition audio track in the preview (crossfades between takes, the
//  music fade-out), the same curves as the export mix, computed from the playback time.
//

import Foundation

/// The preview applies it in its audio tap instead of audio mix ramps: after AVPlayer loops or
/// seeks, those ramps can stay at their last value (0 after a fade-out) and silence the track.
nonisolated struct PreviewEnvelope: Sendable {
    /// One take on a vocal track, or the whole music track.
    struct Part: Sendable {
        let gain: Float
        /// Equal-power fade in over `crossfade` from here; nil when the part starts at full level.
        let fadeInStart: TimeInterval?
        /// Equal-power fade out over `crossfade` from here; nil when the part never fades out.
        let fadeOutStart: TimeInterval?
    }

    let parts: [Part]
    let crossfade: TimeInterval
    /// Linear fade to 0 at the end (music of a partial cover).
    var fadeOutStart: TimeInterval?
    var fadeOutEnd: TimeInterval?

    func gain(at time: TimeInterval) -> Float {
        var total: Float = 0
        for part in parts {
            var gain = part.gain
            if let start = part.fadeInStart {
                if time < start { continue }
                if time < start + crossfade { gain *= Float(sin((time - start) / crossfade * .pi / 2)) }
            }
            if let start = part.fadeOutStart, time >= start {
                if time >= start + crossfade { continue }
                gain *= Float(cos((time - start) / crossfade * .pi / 2))
            }
            total += gain
        }
        if let start = fadeOutStart, let end = fadeOutEnd, time >= start {
            total *= Float(max(0, min(1, (end - time) / max(end - start, 1e-6))))
        }
        return total
    }
}
