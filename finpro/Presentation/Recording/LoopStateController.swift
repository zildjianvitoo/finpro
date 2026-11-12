//
//  LoopStateController.swift
//  finpro
//
//  The recording loop as a pure state machine (PRD §5.6, §6.1):
//  countdown → preRoll → singing → evaluate → singing(next) … → ended.
//  A segment is never repeated: after its evaluation the next one is already being sung.
//  Pause can interrupt any running phase; resuming restarts the current segment with a countdown,
//  so a take never spans a pause.
//  It only decides; RecordingViewModel performs the actions. All times are capture-clock seconds
//  (`now`) or song-timeline seconds (`songTime`), never wall-clock time.
//

import Foundation

nonisolated struct LoopStateController: Sendable {
    enum Phase: Equatable, Sendable {
        case idle
        /// Silent countdown before the first segment and after a pause; `remaining` whole seconds are shown.
        case countdown(remaining: Int)
        /// Reference audio before the segment start; nothing is evaluated yet.
        case preRoll
        case singing
        /// Paused by the user: playback is stopped and nothing is evaluated.
        case paused
        case ended
    }

    enum Action: Equatable, Sendable {
        case none
        case startPlayback(from: TimeInterval)
        case stopPlayback
        case evaluate(segmentIndex: Int)
        case finish
    }

    let segments: [SongSegment]
    let configuration: AppConfiguration
    private(set) var phase: Phase = .idle
    private(set) var segmentIndex = 0
    private var countdownEndsAt: TimeInterval = 0

    init(segments: [SongSegment], configuration: AppConfiguration) {
        self.segments = segments
        self.configuration = configuration
    }

    var currentSegment: SongSegment? { segments.indices.contains(segmentIndex) ? segments[segmentIndex] : nil }
    /// Segments 0..<completedCount were sung to the end (always a prefix, PRD §5.7).
    var completedCount: Int { phase == .ended && segmentIndex >= segments.count ? segments.count : segmentIndex }

    /// The session starts with a silent countdown, so the singer (and the
    /// microphone) are ready before the first note. Playback starts when it ends (`tick`).
    mutating func begin(now: TimeInterval) -> Action {
        guard phase == .idle, currentSegment != nil else { return .none }
        countdownEndsAt = now + TimeInterval(configuration.countdownSeconds)
        phase = .countdown(remaining: configuration.countdownSeconds)
        return .none
    }

    mutating func tick(now: TimeInterval, songTime: TimeInterval?) -> Action {
        switch phase {
        case .idle, .ended, .paused:
            return .none
        case .countdown:
            if now >= countdownEndsAt, let segment = currentSegment {
                phase = .preRoll
                return .startPlayback(from: preRollStart(for: segment))
            }
            phase = .countdown(remaining: max(1, Int((countdownEndsAt - now).rounded(.up))))
            return .none
        case .preRoll, .singing:
            guard let songTime, let segment = currentSegment else { return .none }
            if phase == .preRoll, songTime >= segment.audioStartTime { phase = .singing }
            guard phase == .singing, songTime >= segment.audioEndTime + configuration.evaluationTail else { return .none }
            return .evaluate(segmentIndex: segmentIndex)
        }
    }

    /// The evaluation requested by `.evaluate` is done: the segment counts whatever its score, and
    /// the next one carries on without stopping.
    mutating func segmentEvaluated() -> Action {
        guard phase == .singing else { return .none }
        segmentIndex += 1
        guard segmentIndex < segments.count else {
            phase = .ended
            return .finish
        }
        // Segments tile the timeline, so the next one has already started: keep singing.
        return .none
    }

    /// Whether the user can pause now (a segment is under way).
    var canPause: Bool {
        switch phase {
        case .countdown, .preRoll, .singing: true
        case .idle, .paused, .ended: false
        }
    }

    /// Stops the current segment without logging it.
    mutating func pause() -> Action {
        guard canPause else { return .none }
        let wasPlaying = phase == .preRoll || phase == .singing
        phase = .paused
        return wasPlaying ? .stopPlayback : .none
    }

    /// Restarts the current segment with the usual silent countdown.
    mutating func resume(now: TimeInterval) -> Action {
        guard phase == .paused else { return .none }
        countdownEndsAt = now + TimeInterval(configuration.countdownSeconds)
        phase = .countdown(remaining: configuration.countdownSeconds)
        return .none
    }

    mutating func end() {
        phase = .ended
    }

    /// PRD §5.6: 2 s of reference before the segment (from 0 when not available).
    private func preRollStart(for segment: SongSegment) -> TimeInterval {
        max(0, segment.audioStartTime - configuration.preRoll)
    }
}
