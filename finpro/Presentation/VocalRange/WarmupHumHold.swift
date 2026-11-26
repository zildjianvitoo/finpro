//
//  WarmupHumHold.swift
//  finpro
//

import CoreMedia
import Foundation

/// Counts audible time from the microphone clock, independent of detected pitch.
nonisolated struct WarmupHumHold {
    let threshold: Float
    let maximumGap: TimeInterval

    private(set) var elapsed: TimeInterval = 0
    private var previousSample: TimeInterval?
    private var lastAudibleSample: TimeInterval?

    init(threshold: Float, maximumGap: TimeInterval) {
        self.threshold = threshold
        self.maximumGap = maximumGap
    }

    mutating func ingest(_ sample: PitchSample) -> TimeInterval {
        let time = sample.captureTime.seconds
        guard time.isFinite else {
            self = Self(threshold: threshold, maximumGap: maximumGap)
            return elapsed
        }
        if time == previousSample { return elapsed }
        if let audible = lastAudibleSample, time - audible > maximumGap || time < (previousSample ?? audible) {
            elapsed = 0
            lastAudibleSample = nil
        }
        if sample.rmsDecibels.isFinite, sample.rmsDecibels >= threshold {
            if let previousSample, previousSample == lastAudibleSample {
                elapsed += time - previousSample
            }
            lastAudibleSample = time
        }
        previousSample = time
        return elapsed
    }
}
