//
//  CoverDraft.swift
//  finpro
//

import Foundation

/// Everything the result screen needs to open a saved cover again: the prepared song, the cover
/// plan with its raw videos, every take of the session (retake and continue build on them),
/// the lyrics and the song name. Kept by `CoverDraftStore` under the cover's id.
nonisolated struct CoverDraft: Sendable {
    let song: PreparedSong
    let plan: CompingCompositionPlan
    let attempts: [TakeAttemptLog]
    let lyrics: [LyricLine]
    let songName: String?
}
