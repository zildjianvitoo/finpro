//
//  Array+LyricLine.swift
//  finpro
//
//  Which lyric line is being sung, shared by the two ways the recording screen shows lyrics.
//

import Foundation

extension Array where Element == LyricLine {
    /// The line being sung, or the first song line (`end > 0`) before playback starts so
    /// negative-time lead-in fragments aren't shown while idle.
    func currentIndex(at time: TimeInterval?) -> Int {
        let openingIndex = firstIndex { $0.end > 0 } ?? 0
        guard let time else { return openingIndex }
        return lastIndex { $0.start <= time } ?? openingIndex
    }

    /// The text of a line, or a blank for a position outside the song (so the layout keeps its rows).
    func text(at index: Int) -> String {
        indices.contains(index) ? self[index].text : " "
    }
}
