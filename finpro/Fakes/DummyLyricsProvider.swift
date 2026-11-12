//
//  DummyLyricsProvider.swift
//  finpro
//
//  Debug builds only: placeholder synced lyrics when the real lookup finds none, so the
//  trim screen can be tried with any file. The lines are made up (not from a real song)
//  and spread evenly over the song, with a repeated chorus for the chorus suggestion.
//

#if DEBUG
import Foundation

nonisolated struct DummyLyricsProvider: LyricsProviding {
    /// The real lookup, tried first.
    let base: any LyricsProviding

    /// Shown as the matched title, so the screen can tell placeholder lyrics apart.
    static let placeholderTitle = "Placeholder lyrics"
    /// How long each placeholder line lasts on the song timeline.
    private static let lineDuration: TimeInterval = 4

    private static let verse = [
        "Morning light across the window",
        "Coffee cooling on the sill",
        "Every street I used to walk on",
        "Hums a tune I'm humming still",
    ]
    private static let chorus = [
        "So I sing it out, sing it out loud",
        "Let the echo find its way back home",
        "Every note a little closer now",
        "I don't have to sing alone",
    ]

    func lyrics(title: String, artist: String?, duration: TimeInterval) async throws -> SongLyrics? {
        if let found = try? await base.lyrics(title: title, artist: artist, duration: duration) {
            return found
        }
        return Self.placeholder(duration: duration)
    }

    static func placeholder(duration: TimeInterval) -> SongLyrics {
        let pattern = verse + chorus
        let count = max(1, Int(duration / lineDuration))
        let lines = (0..<count).map { index in
            let text = pattern[index % pattern.count]
            let start = TimeInterval(index) * lineDuration
            let end = min(duration, start + lineDuration)
            return LyricLine(id: index, text: text, start: start, end: end,
                             words: words(in: text, from: start, to: end))
        }
        // The chorus' first occurrence follows the first verse.
        let chorusStart = verse.count
        let chorusRange = count >= chorusStart + chorus.count ? chorusStart..<(chorusStart + chorus.count) : nil
        return SongLyrics(lines: lines, chorus: chorusRange,
                          matchedTitle: placeholderTitle, matchedArtist: "debug build")
    }

    /// Words spread evenly over the line, leaving a short breath at its end.
    private static func words(in text: String, from start: TimeInterval, to end: TimeInterval) -> [LyricWord] {
        let parts = text.split(separator: " ").map(String.init)
        let sung = (end - start) * 0.85
        let step = sung / Double(max(1, parts.count))
        return parts.enumerated().map { index, word in
            LyricWord(text: word, start: start + Double(index) * step, end: start + Double(index + 1) * step)
        }
    }
}
#endif
