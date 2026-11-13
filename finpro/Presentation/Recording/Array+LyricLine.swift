//
//  Array+LyricLine.swift
//  finpro
//
//  Which lyric line is being sung, shared by the two ways the recording screen shows lyrics.
//

import Foundation

extension Array where Element == LyricLine {
    /// The line being sung, or the first one before the song starts.
    func currentIndex(at time: TimeInterval?) -> Int {
        guard let time else { return 0 }
        return lastIndex { $0.start <= time } ?? 0
    }

    /// The text of a line, or a blank for a position outside the song (so the layout keeps its rows).
    func text(at index: Int) -> String {
        indices.contains(index) ? self[index].text : " "
    }
}
