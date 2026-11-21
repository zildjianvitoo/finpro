//
//  PreparedSong.swift
//  finpro
//
//  CONTRACT — owned by the whole team. See docs/COLLABORATION.md before editing.
//  `leadIn` added 2026-11-21 with the user's OK.
//  Handoff: Ikzaz (preparation) -> Takin (recording) and Zildjian (comping).
//

import Foundation

nonisolated struct PreparedSong: Sendable {
    /// Full mix, already transposed by `transposition.semitoneShift`.
    let earphoneMixURL: URL
    /// No original vocals, transposed by the SAME `semitoneShift`, starts at t = 0.
    let instrumentalURL: URL
    let segments: [SongSegment]
    let transposition: TranspositionPlan
    /// Duration of the trimmed song in seconds.
    let duration: TimeInterval
    let separationMethod: StemSeparationMethod
    /// The song just before the trimmed part, in the same key, heard in the pre-roll before 0 so
    /// the singer hears the beat instead of silence (added 2026-11-21 with the user's OK). Nil when
    /// the part starts at the song's start, or it couldn't be prepared: the pre-roll is silent there.
    var leadIn: LeadIn?

    nonisolated struct LeadIn: Sendable {
        /// Full mix, transposed like `earphoneMixURL`; it ends where the trimmed song starts.
        let mixURL: URL
        /// No original vocals, transposed like `instrumentalURL`.
        let instrumentalURL: URL
        /// Seconds of song before 0, at most `AppConfiguration.preRoll`.
        let duration: TimeInterval

        init(mixURL: URL, instrumentalURL: URL, duration: TimeInterval) {
            self.mixURL = mixURL
            self.instrumentalURL = instrumentalURL
            self.duration = duration
        }
    }
}
