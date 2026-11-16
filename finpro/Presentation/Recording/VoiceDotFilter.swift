//
//  VoiceDotFilter.swift
//  finpro
//
//  Where the lime voice dot on the pitch guide sits. Display only: the hit/miss colours and the
//  score still use every raw sample. Raw live pitch flickers: a consonant or breath gives one
//  frame without pitch, a mistracked frame jumps several semitones, and the pitch wobbles a
//  little within a held note. The dot therefore
//  - ignores frames without pitch (it stays where it was; the view fades it once the voice
//    has been gone for a moment),
//  - takes the median of the last 3 voiced frames, so one stray frame never moves it,
//  - eases small changes and jumps to real note changes.
//

import Foundation

nonisolated struct VoiceDotFilter: Sendable {
    /// A longer silence than this starts the dot fresh (a new phrase), without easing from the old note.
    static let phraseGap: TimeInterval = 0.3
    /// Changes smaller than this (semitones) are eased; larger ones are a new note and shown at once.
    static let noteChange: Float = 1
    /// Share of a small change applied per frame (lower = calmer, but slower).
    static let easing: Float = 0.35

    private var recent: [Float] = []
    /// The dot's pitch (MIDI, may be fractional), nil before any voice.
    private(set) var midi: Float?
    /// Song time of the last frame with pitch.
    private(set) var lastVoicedTime: TimeInterval?

    /// - Parameter foldToDot: the sample has no guide note to fold it to (between notes); it is
    ///   moved by octaves next to the dot, so the dot does not jump an octave between notes.
    mutating func update(midi raw: Float?, time: TimeInterval, foldToDot: Bool = false) {
        guard var raw, raw.isFinite, time.isFinite else { return }
        if let lastVoicedTime, time - lastVoicedTime > Self.phraseGap || time < lastVoicedTime { reset() }
        if foldToDot, let midi { raw += 12 * ((midi - raw) / 12).rounded() }
        recent.append(raw)
        if recent.count > 3 { recent.removeFirst() }
        let median = recent.sorted()[recent.count / 2]
        if let shown = midi, abs(median - shown) < Self.noteChange {
            midi = shown + Self.easing * (median - shown)
        } else {
            midi = median
        }
        lastVoicedTime = time
    }

    mutating func reset() {
        recent.removeAll()
        midi = nil
        lastVoicedTime = nil
    }
}
