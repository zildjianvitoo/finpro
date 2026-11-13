//
//  RecordingPass.swift
//  finpro
//
//  What one visit to the recording screen records: the whole song (the session), one clip again
//  (Retake on the result screen) or the rest of the song (Continue Recording). Each pass writes its
//  own raw video; the earlier ones stay in the cover (`CompingCompositionPlan.rawVideoURLs`).
//

import Foundation

struct RecordingPass: Equatable {
    enum Kind: Equatable {
        case session
        case retake(segment: Int)
        case continueFrom(segment: Int)
    }

    /// A frame of the clip next to the one being recorded, shown over the camera to line up with.
    struct AlignmentFrame: Equatable {
        let videoURL: URL
        /// File time inside `videoURL`.
        let time: TimeInterval
    }

    let kind: Kind
    /// Raw videos of the passes before this one, in pass order.
    let earlierRawVideoURLs: [URL]
    var alignmentFrame: AlignmentFrame?

    static let session = RecordingPass(kind: .session, earlierRawVideoURLs: [])

    /// `TakeAttemptLog.recordingPass` of the takes sung now.
    var index: Int { earlierRawVideoURLs.count }

    var isSession: Bool { kind == .session }

    /// The segments sung in this pass.
    func segmentRange(segmentCount: Int) -> Range<Int> {
        switch kind {
        case .session: 0..<segmentCount
        case .retake(let segment): segment..<(segment + 1)
        case .continueFrom(let segment): segment..<segmentCount
        }
    }
}
