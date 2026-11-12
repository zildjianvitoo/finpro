//
//  TakeAttemptLog.swift
//  finpro
//
//  CONTRACT — owned by the whole team. See docs/COLLABORATION.md before editing.
//  Handoff: Takin (recording) -> Zildjian (comping).
//

import CoreMedia
import Foundation

nonisolated enum SegmentAttemptStatus: String, Sendable, Codable {
    /// Scored at or above the pass threshold (the session repeated failed segments).
    case passed
    case failed
    /// Sung to the end and kept in the cover whatever the score (the session no longer repeats
    /// segments); `accuracyScore` still holds the measured score.
    case completed

    var displayLabel: String {
        switch self {
        case .passed: "PASSED"
        case .completed: "DONE"
        case .failed: "TRY AGAIN"
        }
    }
}

nonisolated struct TakeAttemptLog: Identifiable, Sendable {
    let id: UUID
    /// Zero-based, matches `SongSegment.index`.
    let segmentIndex: Int
    /// 1-based, per segment.
    let attemptNumber: Int
    /// File time inside RawMasterVideo.mov, aligned to what the user heard
    /// (latency compensated), INCLUDING the crossfade handle on both sides.
    let videoTimeRange: CMTimeRange
    /// 0.0 ... 1.0
    let accuracyScore: Float
    let missedNoteIDs: [UUID]
    let status: SegmentAttemptStatus

    init(id: UUID = UUID(), segmentIndex: Int, attemptNumber: Int, videoTimeRange: CMTimeRange, accuracyScore: Float, missedNoteIDs: [UUID], status: SegmentAttemptStatus) {
        self.id = id
        self.segmentIndex = segmentIndex
        self.attemptNumber = attemptNumber
        self.videoTimeRange = videoTimeRange
        self.accuracyScore = accuracyScore
        self.missedNoteIDs = missedNoteIDs
        self.status = status
    }
}
