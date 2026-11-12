//
//  LoopStateControllerChecks.swift
//  finpro
//
//  Executable checks for the recording loop state machine (TK-10). Not part of the app target.
//

import Foundation

nonisolated enum LoopStateControllerChecks {
    static func run() throws -> Int {
        var count = 0
        func check(_ condition: Bool, _ message: String) throws {
            count += 1
            if !condition { throw ContractViolation(contract: "LoopStateController", message: message) }
        }
        let configuration = AppConfiguration.default
        let segments = DomainFixtures.segments  // 0–6, 6–9 (instrumental), 9–16
        var loop = LoopStateController(segments: segments, configuration: configuration)

        // Start: silent countdown, then pre-roll from 0.
        try check(loop.begin(now: -3) == .none, "begin waits for the countdown")
        try check(loop.phase == .countdown(remaining: configuration.countdownSeconds), "countdown first")
        try check(loop.tick(now: -0.5, songTime: nil) == .none && loop.phase == .countdown(remaining: 1), "counting down")
        try check(loop.tick(now: 0, songTime: nil) == .startPlayback(from: 0), "first segment plays from 0")
        try check(loop.phase == .preRoll, "pre-roll")
        try check(loop.tick(now: 0, songTime: 0) == .none && loop.phase == .singing, "segment start → singing")
        try check(loop.tick(now: 6, songTime: 6) == .none, "no evaluation before end + tail")
        try check(loop.tick(now: 6.2, songTime: 6.2) == .evaluate(segmentIndex: 0), "evaluate after end + tail")

        // Whatever the score, the next segment carries on without stopping or repeating.
        try check(loop.segmentEvaluated() == .none, "evaluation keeps playing")
        try check(loop.segmentIndex == 1 && loop.phase == .singing, "next segment is singing")
        try check(loop.completedCount == 1, "one segment completed")
        try check(loop.tick(now: 9.2, songTime: 9.2) == .evaluate(segmentIndex: 1), "evaluate segment 2")
        _ = loop.segmentEvaluated()
        try check(loop.tick(now: 16.2, songTime: 16.2) == .evaluate(segmentIndex: 2), "evaluate segment 3")

        // The last segment finishes the session; every segment is complete.
        try check(loop.segmentEvaluated() == .finish, "last segment finishes")
        try check(loop.phase == .ended && loop.completedCount == segments.count, "all segments completed")

        // Pause stops the segment; resuming counts down and restarts it with the pre-roll.
        var paused = LoopStateController(segments: segments, configuration: configuration)
        _ = paused.begin(now: -3)
        _ = paused.tick(now: 0, songTime: nil)
        _ = paused.tick(now: 0, songTime: 0)
        _ = paused.tick(now: 6.2, songTime: 6.2)
        _ = paused.segmentEvaluated()
        try check(paused.canPause, "can pause while singing")
        try check(paused.pause() == .stopPlayback && paused.phase == .paused, "pause stops playback")
        try check(paused.tick(now: 10, songTime: nil) == .none, "nothing happens while paused")
        try check(paused.resume(now: 10) == .none && paused.phase == .countdown(remaining: configuration.countdownSeconds), "resume counts down")
        try check(paused.tick(now: 13, songTime: nil) == .startPlayback(from: max(0, 6 - configuration.preRoll)), "resume restarts the current segment with pre-roll")
        try check(paused.segmentIndex == 1 && paused.completedCount == 1, "resume keeps the completed segments")

        // Deleting the last segment goes back one segment, with the countdown, and sings it again.
        var back = LoopStateController(segments: segments, configuration: configuration)
        _ = back.begin(now: -3)
        _ = back.tick(now: 0, songTime: nil)
        _ = back.tick(now: 0, songTime: 0)
        _ = back.tick(now: 6.2, songTime: 6.2)
        _ = back.segmentEvaluated()
        try check(back.segmentIndex == 1 && back.completedCount == 1, "one segment completed before deleting")
        try check(back.goBackOneSegment(now: 7) == .stopPlayback, "delete stops playback")
        try check(back.segmentIndex == 0 && back.completedCount == 0, "back on the first segment")
        try check(back.phase == .countdown(remaining: configuration.countdownSeconds), "countdown before singing again")
        try check(back.tick(now: 10, songTime: nil) == .startPlayback(from: 0), "first segment is sung again from the start")
        try check(back.goBackOneSegment(now: 11) == .stopPlayback && back.segmentIndex == 0, "on the first segment, delete stays there")
        _ = back.tick(now: 13, songTime: 0)
        _ = back.pause()
        try check(back.goBackOneSegment(now: 14) == .none && back.phase == .countdown(remaining: configuration.countdownSeconds), "delete from a pause counts down")
        var finished = LoopStateController(segments: [segments[0]], configuration: configuration)
        _ = finished.begin(now: -3)
        _ = finished.tick(now: 0, songTime: nil)
        _ = finished.tick(now: 0, songTime: 0)
        _ = finished.tick(now: 6.2, songTime: 6.2)
        _ = finished.segmentEvaluated()
        try check(finished.goBackOneSegment(now: 7) == .none && finished.phase == .ended, "nothing to delete once the session has ended")

        // Ending early keeps the completed prefix.
        var early = LoopStateController(segments: segments, configuration: configuration)
        _ = early.begin(now: -3)
        _ = early.tick(now: 0, songTime: nil)
        _ = early.tick(now: 0, songTime: 0)
        _ = early.tick(now: 6.2, songTime: 6.2)
        _ = early.segmentEvaluated()
        early.end()
        try check(early.completedCount == 1, "early end keeps 1 completed: \(early.completedCount)")
        return count
    }
}
