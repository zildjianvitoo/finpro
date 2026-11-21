//
//  GuideWordLabels.swift
//  finpro
//
//  The word drawn under each pitch guide note (recording guide and cover preview). Built once per
//  song: a guide built from the lyrics has one note per word, starting where the word's voice
//  starts, so each word goes on the note that overlaps it most.
//

import Foundation

nonisolated enum GuideWordLabels {
    static func make(words: [LyricWord], notes: [PianoRollView.Note]) -> [UUID: String] {
        let sorted = notes.sorted { $0.start < $1.start }
        var labels: [UUID: String] = [:]
        var first = 0
        for word in words.sorted(by: { $0.start < $1.start }) {
            // Notes that end before this word can't overlap it or any later word.
            while first < sorted.count && sorted[first].end <= word.start { first += 1 }
            var best: (id: UUID, overlap: TimeInterval)?
            var index = first
            while index < sorted.count && sorted[index].start < word.end {
                let note = sorted[index]
                let overlap = min(note.end, word.end) - max(note.start, word.start)
                if labels[note.id] == nil, overlap > 0, overlap > (best?.overlap ?? 0) {
                    best = (note.id, overlap)
                }
                index += 1
            }
            if let best { labels[best.id] = word.text }
        }
        return labels
    }
}
