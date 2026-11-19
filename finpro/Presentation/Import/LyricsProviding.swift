//
//  LyricsProviding.swift
//  finpro
//
//  Time-synced lyrics for the trim screen, so the user can see what is sung in the part they pick.
//  Times are seconds on the whole imported song. Implemented by LRCLibLyricsProvider (Data).
//

import Foundation

nonisolated struct LyricWord: Equatable, Sendable, Codable {
    let text: String
    let start: TimeInterval
    let end: TimeInterval
}

nonisolated struct LyricLine: Equatable, Sendable, Identifiable, Codable {
    let id: Int
    let text: String
    let start: TimeInterval
    /// Start of the next line or break (or the song's end).
    let end: TimeInterval
    /// Estimated: the source only times whole lines.
    let words: [LyricWord]

    /// Keep only the sung portion intersecting the selection, on the excerpt's timeline.
    func clipped(to selection: ClosedRange<TimeInterval>) -> LyricLine? {
        let lower = max(start, selection.lowerBound)
        let upper = min(end, selection.upperBound)
        guard lower < upper else { return nil }
        let offset = selection.lowerBound
        let kept = words.compactMap { word -> LyricWord? in
            let from = max(lower, word.start)
            let to = min(upper, word.end)
            guard from < to else { return nil }
            return LyricWord(text: word.text, start: from - offset, end: to - offset)
        }
        // Without word timing only an entirely selected line can be shown reliably.
        guard !kept.isEmpty || (words.isEmpty && lower == start && upper == end) else { return nil }
        let selectedText = kept.count == words.count ? text : kept.map(\.text).joined(separator: " ")
        return LyricLine(id: id, text: selectedText, start: lower - offset, end: upper - offset, words: kept)
    }
}

nonisolated struct SongLyrics: Equatable, Sendable, Codable {
    let lines: [LyricLine]
    /// Indices into `lines` of the chorus' first occurrence (the most repeated block), if any.
    let chorus: Range<Int>?
    /// What the source matched, e.g. "Abadi (Indo Version) – Dendi Nata".
    let matchedTitle: String
    let matchedArtist: String
}

nonisolated enum LyricsLookupError: Error, Equatable {
    /// No connection, timeout, or the service is busy or down.
    case unavailable
}

nonisolated protocol LyricsProviding: Sendable {
    /// Synced lyrics for a song of `duration` seconds, or nil if none match.
    func lyrics(title: String, artist: String?, duration: TimeInterval) async throws -> SongLyrics?
}
