//
//  LyricGuideNotesUseCase.swift
//  finpro
//
//  Builds the pitch guide from the lyrics: one note per sung word, so every block has its word
//  (device feedback 2026-11-13). The lyrics only time whole lines, so each line's words are
//  spread by syllable count over the parts of the line where the vocal guide is actually voiced
//  (the notes CREPE found), not over the silence or the instrumental around them. Each word's
//  pitch is the one its voiced part holds longest. Pure: no audio here.
//

import Foundation

nonisolated struct LyricGuideNotesUseCase: Sendable {
    /// One lyric line on the prepared song's timeline. `wordWeights` is one weight per word
    /// (its syllable count), in order.
    struct Line: Sendable, Equatable {
        let start: TimeInterval
        let end: TimeInterval
        let wordWeights: [Double]

        init(start: TimeInterval, end: TimeInterval, wordWeights: [Double]) {
            self.start = start
            self.end = end
            self.wordWeights = wordWeights
        }
    }

    /// Where a word is sung, and its note (nil when nothing was voiced in its line).
    struct Word: Sendable, Equatable {
        let start: TimeInterval
        let end: TimeInterval
        let note: TargetMIDINote?
    }

    struct Result: Sendable {
        /// The guide: the words' notes, sorted and non-overlapping.
        let notes: [TargetMIDINote]
        /// `words[line][word]`, the same shape as the input lines.
        let words: [[Word]]
    }

    /// A word further than this from the middle pitch of its line is taken as an octave error of
    /// the pitch tracker (a harmonic or a backing voice) and moved an octave toward the line.
    /// A real leap inside one line is rarely wider than a sixth.
    static let octaveErrorDistance = 10
    /// Lines with fewer notes than this use the whole guide's middle pitch instead.
    static let minimumNotesForLineMiddle = 3
    /// Below this much voiced time a line is treated as not sung (bleed, a breath).
    static let minimumVoicedPerLine: TimeInterval = 0.2
    private static let epsilon: TimeInterval = 1e-6

    /// `pitchNotes`: the notes found in the vocal guide (original key), any order.
    func execute(pitchNotes: [TargetMIDINote], lines: [Line]) -> Result {
        let pitched = pitchNotes
            .filter { $0.startTime.isFinite && $0.endTime.isFinite && $0.duration > 0 }
            .sorted { $0.startTime < $1.startTime }
        var notes: [TargetMIDINote] = []
        var words: [[Word]] = []
        for line in lines {
            let lineWords = sungWords(in: line, pitched: pitched, after: notes.last?.endTime ?? 0)
            notes += lineWords.compactMap(\.note)
            words.append(lineWords)
        }
        let guideMiddle = Self.middle(notes.map(\.midiNote))
        words = words.map { line in
            let pitches = line.compactMap(\.note?.midiNote)
            let middle = pitches.count >= Self.minimumNotesForLineMiddle ? Self.middle(pitches) : guideMiddle
            return line.map { word in
                guard let note = word.note, let middle else { return word }
                let pitch = Self.folded(note.midiNote, toward: middle)
                return pitch == note.midiNote ? word : Word(start: word.start, end: word.end,
                    note: TargetMIDINote(id: note.id, midiNote: pitch, startTime: note.startTime, duration: note.duration))
            }
        }
        return Result(notes: words.flatMap { $0.compactMap(\.note) }, words: words)
    }

    /// Moves `pitch` by octaves while it is more than `octaveErrorDistance` from `middle`.
    static func folded(_ pitch: Int, toward middle: Double) -> Int {
        var result = pitch
        while Double(result) - middle > Double(octaveErrorDistance), result - 12 >= 0 { result -= 12 }
        while middle - Double(result) > Double(octaveErrorDistance), result + 12 <= 127 { result += 12 }
        return result
    }

    private static func middle(_ pitches: [Int]) -> Double? {
        let sorted = pitches.sorted()
        guard !sorted.isEmpty else { return nil }
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? Double(sorted[mid - 1] + sorted[mid]) / 2 : Double(sorted[mid])
    }

    private func sungWords(in line: Line, pitched: [TargetMIDINote], after previousEnd: TimeInterval) -> [Word] {
        let weights = line.wordWeights.map { $0.isFinite && $0 > 0 ? $0 : 1 }
        guard !weights.isEmpty, line.end > line.start else { return [] }
        let start = max(line.start, previousEnd)
        // The voiced parts of the line, in order.
        let voiced = pitched.compactMap { note -> ClosedRange<TimeInterval>? in
            let lower = max(note.startTime, start), upper = min(note.endTime, line.end)
            return upper - lower > Self.epsilon ? lower...upper : nil
        }
        let voicedTotal = voiced.reduce(0) { $0 + $1.upperBound - $1.lowerBound }
        let total = weights.reduce(0, +)
        guard voicedTotal >= Self.minimumVoicedPerLine else {
            // Not sung here as far as the guide can tell: spread evenly, without notes.
            var time = start
            let span = max(0, line.end - start)
            return weights.map { weight in
                defer { time += span * weight / total }
                return Word(start: time, end: time + span * weight / total, note: nil)
            }
        }
        var words: [Word] = []
        var share = 0.0
        for weight in weights {
            let from = position(share / total * voicedTotal, in: voiced, atEnd: false)
            share += weight
            let to = position(share / total * voicedTotal, in: voiced, atEnd: true)
            let note = to - from > Self.epsilon
                ? dominantPitch(from: from, to: to, in: pitched).map { TargetMIDINote(midiNote: $0, startTime: from, duration: to - from) }
                : nil
            words.append(Word(start: from, end: max(from, to), note: note))
        }
        return words
    }

    /// The song time `offset` seconds into the voiced parts. At a boundary between two parts, the
    /// start of a word goes to the next part and the end of a word stays at the end of the earlier one.
    private func position(_ offset: TimeInterval, in voiced: [ClosedRange<TimeInterval>], atEnd: Bool) -> TimeInterval {
        var remaining = offset
        for (index, part) in voiced.enumerated() {
            let length = part.upperBound - part.lowerBound
            let isLast = index == voiced.count - 1
            if remaining < length - Self.epsilon || (atEnd && remaining <= length + Self.epsilon) || isLast {
                return min(part.lowerBound + max(remaining, 0), part.upperBound)
            }
            remaining -= length
        }
        return voiced.last?.upperBound ?? 0
    }

    /// The pitch held longest between `from` and `to` (nil when nothing is voiced there).
    private func dominantPitch(from: TimeInterval, to: TimeInterval, in pitched: [TargetMIDINote]) -> Int? {
        var held: [Int: TimeInterval] = [:]
        for note in pitched where note.endTime > from && note.startTime < to {
            held[note.midiNote, default: 0] += min(note.endTime, to) - max(note.startTime, from)
        }
        // Ties go to the lower pitch, so the result does not depend on dictionary order.
        return held.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key
    }
}
