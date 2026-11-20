//
//  AppConfiguration.swift
//  finpro
//
//  CONTRACT — owned by the whole team. See docs/COLLABORATION.md before editing.
//  Every tunable number lives here. Never hard-code these values elsewhere.
//

import Foundation

nonisolated struct AppConfiguration: Sendable, Equatable, Codable {
    // Evaluation
    /// 0.75 → 0.30 on 2026-11-20: scored with the app's own rules, the original vocal passed only
    /// 45% of lines at 0.75 and a monotone voice still fails nearly all at 0.30.
    var passThreshold: Float = 0.30
    var hitToleranceCents: Float = 80
    var noiseGateDBFS: Float = -40
    var pitchHop: TimeInterval = 0.05
    var attackIgnore: TimeInterval = 0.10
    var timingTolerance: TimeInterval = 0.10
    /// 0.50 → 0.30 on 2026-11-20: the original vocal had 27% of its notes red at 0.50, 7% at 0.30.
    var missedNoteThreshold: Float = 0.30

    // Segmentation
    var segmentGap: TimeInterval = 0.8
    var minSegment: TimeInterval = 3.0
    var maxSegment: TimeInterval = 8.0

    // Session
    /// Reference heard before every segment start (session start, resume, sing again). It starts
    /// before 0 when the song gives less: silence first, while the guide already moves.
    /// 2.0 → 3.0 on 2026-11-20, when it replaced the countdown.
    var preRoll: TimeInterval = 3.0
    /// Silent countdown before the pre-roll. 3 → 0 on 2026-11-20: it covered the pitch guide, and
    /// the pre-roll (with a small 3-2-1) now gets the singer ready.
    var countdownSeconds: Int = 0
    var maxSessionDuration: TimeInterval = 15 * 60
    var manualLatencyCalibration: TimeInterval = 0
    var evaluationTail: TimeInterval = 0.15

    // Comping
    /// Take handle and transition length at each cut: the vocals crossfade (equal power) and the
    /// video dissolves over this time, centred on the boundary. 30 ms → 150 ms on 2026-11-04 (smoother cuts).
    var crossfade: TimeInterval = 0.15
    var partialExportFadeOut: TimeInterval = 1.0
    var vocalGain: Float = 1.0
    var instrumentalGain: Float = 0.8

    static let `default` = AppConfiguration()
}
