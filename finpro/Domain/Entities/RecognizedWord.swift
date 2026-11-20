//
//  RecognizedWord.swift
//  finpro
//
//  CONTRACT — owned by the whole team. See docs/COLLABORATION.md before editing.
//  Added 2026-11-20 with the user's OK (sung word recognition for the lyric guide).
//

import Foundation

/// A word heard in the song's vocal stem by on-device speech recognition, on the trimmed
/// reference's timeline. Used only to place the lyrics' words; its spelling may differ from them.
nonisolated struct RecognizedWord: Sendable, Equatable {
    let text: String
    /// Seconds from the start of the trimmed reference.
    let startTime: TimeInterval
    let endTime: TimeInterval

    init(text: String, startTime: TimeInterval, endTime: TimeInterval) {
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
    }
}
