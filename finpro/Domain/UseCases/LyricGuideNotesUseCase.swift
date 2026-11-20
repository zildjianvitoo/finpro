//
//  LyricGuideNotesUseCase.swift
//  finpro
//
//  Builds the pitch guide from the lyrics: one note per sung word, so every block has its word
//  (device feedback 2026-11-13). The lyrics only time whole lines, and often from another
//  release of the song, so first the lines are moved onto where the vocal guide (the notes CREPE
//  found) goes from silent to voiced. Then each line's words are spread by syllable count over the line
//  up to its last voiced moment, a held note and a silent gap counting only up to a cap, so a
//  long held word no longer pushes the words before it late (device feedback 2026-11-20). Each
//  word's pitch is the one its voiced part holds longest. Pure: no audio here.
//
//  Measured against word timestamps of three songs' vocal stems (A Whole New World, Best Part,
//  Abadi): median word start error 0.72 s before, 0.19 s after (0.24 s on 15 s clips).
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
        /// How far the lines were moved to where they are sung (seconds, negative = earlier).
        var lineShift: TimeInterval = 0
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

    // Moving the lines (synced lyrics are often 0.5–1.5 s off for a given recording).
    /// The lines are tried this far earlier and later. Wider lets a short clip jump to the
    /// neighbouring phrase.
    static let lineShiftRange: TimeInterval = 1.5
    static let lineShiftStep: TimeInterval = 0.05
    /// A line start fits where the guide is voiced for this long after it and silent before it.
    static let lineStartWindow: TimeInterval = 0.5
    /// The pitch tracker's first note of a phrase comes this long after it is sung (a consonant or a
    /// soft attack has no steady pitch yet), so the lines start this much before it.
    static let attackLead: TimeInterval = 0.35
    /// With fewer lines the shift is not reliable and the lines stay where they are.
    static let minimumLinesForShift = 2

    // Spreading the words over a line.
    /// A voiced part counts up to this long: a held note is one sung sound, not many syllables.
    static let heldNoteShare: TimeInterval = 0.2
    /// A note covering less voice than this is grown to it (inside its word): the tracker often
    /// hears only the tail of a soft word, and a 0.05 s block can't be seen or sung.
    static let minimumNoteLength: TimeInterval = 0.3
    /// A silent part counts up to this long: the tracker misses soft syllables, so a short gap may
    /// hold one, but a long rest holds none.
    static let silenceShare: TimeInterval = 0.5

    /// `pitchNotes`: the notes found in the vocal guide (original key), any order.
    func execute(pitchNotes: [TargetMIDINote], lines: [Line]) -> Result {
        let pitched = pitchNotes
            .filter { $0.startTime.isFinite && $0.endTime.isFinite && $0.duration > 0 }
            .sorted { $0.startTime < $1.startTime }
        let shift = Self.lineShift(lines: lines, pitched: pitched)
        var notes: [TargetMIDINote] = []
        var words: [[Word]] = []
        for unshifted in lines {
            let line = Line(start: unshifted.start + shift, end: unshifted.end + shift, wordWeights: unshifted.wordWeights)
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
        words = Self.foldedAgainstNeighbours(words)
        return Result(notes: words.flatMap { $0.compactMap(\.note) }, words: words, lineShift: shift)
    }

    /// The shift that puts the line starts where the vocal guide goes from silent to voiced, minus
    /// the attack lead; 0 with too few lines.
    static func lineShift(lines: [Line], pitched: [TargetMIDINote]) -> TimeInterval {
        guard lines.count >= minimumLinesForShift, !pitched.isEmpty else { return 0 }
        func voicedShare(_ from: TimeInterval, _ to: TimeInterval) -> Double {
            pitched.reduce(0) { $0 + max(0, min($1.endTime, to) - max($1.startTime, from)) } / (to - from)
        }
        let steps = Int((lineShiftRange / lineShiftStep).rounded())
        var best: TimeInterval = 0
        var bestCost = Double.infinity
        for step in -steps...steps {
            let shift = Double(step) * lineShiftStep
            // A tiny cost per second keeps the smaller shift when two fit equally well.
            var cost = abs(shift) * 1e-3
            for line in lines {
                let time = line.start + shift
                cost -= voicedShare(time, time + lineStartWindow) - voicedShare(time - lineStartWindow, time)
            }
            if cost < bestCost {
                bestCost = cost
                best = shift
            }
        }
        return best - attackLead
    }

    /// Notes on each side compared with a word in the second octave pass.
    static let neighbourCount = 3

    /// Second octave pass, across line boundaries: a word more than `octaveErrorDistance` from the
    /// middle of the words around it moves an octave toward them. The line pass misses an octave
    /// error that pulls its own line's middle up (one high word in a short line).
    private static func foldedAgainstNeighbours(_ words: [[Word]]) -> [[Word]] {
        let positions = words.indices.flatMap { line in
            words[line].indices.compactMap { words[line][$0].note == nil ? nil : (line, $0) }
        }
        var pitches = positions.map { words[$0.0][$0.1].note!.midiNote }
        var result = words
        for index in pitches.indices {
            let around = (max(0, index - neighbourCount)..<min(pitches.count, index + neighbourCount + 1))
                .filter { $0 != index }.map { pitches[$0] }
            guard around.count >= minimumNotesForLineMiddle, let middle = middle(around) else { continue }
            let pitch = foldedAgainstNeighbours(pitches[index], toward: middle)
            guard pitch != pitches[index] else { continue }
            pitches[index] = pitch
            let (line, word) = positions[index]
            let old = result[line][word]
            let note = old.note!
            result[line][word] = Word(start: old.start, end: old.end,
                                      note: TargetMIDINote(id: note.id, midiNote: pitch, startTime: note.startTime,
                                                           duration: note.duration))
        }
        return result
    }

    /// Neighbour pass: six words around are a steadier reference than one line, so a word this far
    /// (a minor seventh or more) from their middle moves an octave when that brings it closer.
    static let neighbourOctaveErrorDistance = 10

    /// The neighbour pass for a guide without lyrics: the raw pitch notes in time order.
    static func foldingOctaveErrors(_ notes: [TargetMIDINote]) -> [TargetMIDINote] {
        var sorted = notes.sorted { $0.startTime < $1.startTime }
        for index in sorted.indices {
            let around = (max(0, index - neighbourCount)..<min(sorted.count, index + neighbourCount + 1))
                .filter { $0 != index }.map { sorted[$0].midiNote }
            guard around.count >= minimumNotesForLineMiddle, let middle = middle(around) else { continue }
            let note = sorted[index]
            let pitch = foldedAgainstNeighbours(note.midiNote, toward: middle)
            if pitch != note.midiNote {
                sorted[index] = TargetMIDINote(id: note.id, midiNote: pitch, startTime: note.startTime, duration: note.duration)
            }
        }
        return sorted
    }

    static func foldedAgainstNeighbours(_ pitch: Int, toward middle: Double) -> Int {
        var result = pitch
        while abs(Double(result) - middle) >= Double(neighbourOctaveErrorDistance) {
            let step = Double(result) > middle ? -12 : 12
            guard (0...127).contains(result + step),
                  abs(Double(result + step) - middle) < abs(Double(result) - middle) else { break }
            result += step
        }
        return result
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
        // From the line's start to its last voiced moment: silent and voiced parts, each counting
        // only up to its cap.
        var pieces: [Piece] = []
        var time = start
        for part in voiced {
            // Overlapping pitch notes would make the pieces run backwards: each starts where the last ended.
            let lower = max(part.lowerBound, time)
            guard part.upperBound - lower > Self.epsilon else { continue }
            if lower > time + Self.epsilon {
                pieces.append(Piece(range: time...lower, share: min(lower - time, Self.silenceShare)))
            }
            pieces.append(Piece(range: lower...part.upperBound, share: min(part.upperBound - lower, Self.heldNoteShare)))
            time = part.upperBound
        }
        let shareTotal = pieces.reduce(0) { $0 + $1.share }
        var words: [Word] = []
        var done = 0.0
        for weight in weights {
            let from = position(done / total * shareTotal, in: pieces)
            done += weight
            let to = max(from, position(done / total * shareTotal, in: pieces))
            words.append(Word(start: from, end: to, note: noteFor(from: from, to: to, voiced: voiced, pitched: pitched)))
        }
        return words
    }

    /// The word's note. It starts where the word's voice starts and is held until the next word,
    /// as a singer holds a word: the word's leading silence (a breath, or a soft start the tracker
    /// didn't hear) is left out, since a note there is scored as missed even in a good take
    /// (device feedback 2026-11-20). When the tracker heard only a sliver of the word, the start
    /// moves back so the note is at least `minimumNoteLength`. A word the tracker heard no pitch
    /// in (a soft "I" before a phrase) is still sung: it gets a note over its whole time with the
    /// nearest pitch of its line.
    private func noteFor(from: TimeInterval, to: TimeInterval, voiced: [ClosedRange<TimeInterval>],
                         pitched: [TargetMIDINote]) -> TargetMIDINote? {
        guard to - from > Self.epsilon else { return nil }
        let inside = voiced.compactMap { part -> ClosedRange<TimeInterval>? in
            let lower = max(part.lowerBound, from), upper = min(part.upperBound, to)
            return upper - lower > Self.epsilon ? lower...upper : nil
        }
        if let first = inside.first, let last = inside.last,
           let midi = dominantPitch(from: from, to: to, in: pitched) {
            // Long enough to be seen and sung: grown around the voice, inside the word.
            let length = min(max(last.upperBound - first.lowerBound, Self.minimumNoteLength), to - from)
            let middle = (first.lowerBound + last.upperBound) / 2
            let start = min(max(middle - length / 2, from), to - length)
            return TargetMIDINote(midiNote: midi, startTime: start, duration: to - start)
        }
        return nearestPitch(to: from, in: voiced, pitched: pitched)
            .map { TargetMIDINote(midiNote: $0, startTime: from, duration: to - from) }
    }

    /// The pitch of the voiced part of the line closest to `time`.
    private func nearestPitch(to time: TimeInterval, in voiced: [ClosedRange<TimeInterval>], pitched: [TargetMIDINote]) -> Int? {
        let distance = { (part: ClosedRange<TimeInterval>) in
            part.contains(time) ? 0 : min(abs(part.lowerBound - time), abs(part.upperBound - time))
        }
        guard let part = voiced.min(by: { distance($0) < distance($1) }) else { return nil }
        return dominantPitch(from: part.lowerBound, to: part.upperBound, in: pitched)
    }

    private struct Piece {
        let range: ClosedRange<TimeInterval>
        /// How much of the line's time it counts for.
        let share: TimeInterval
    }

    /// The song time `share` into the pieces, each piece's share mapped evenly onto its time.
    private func position(_ share: TimeInterval, in pieces: [Piece]) -> TimeInterval {
        var remaining = share
        for piece in pieces {
            if remaining <= piece.share + Self.epsilon {
                let fraction = piece.share > 0 ? min(max(remaining, 0) / piece.share, 1) : 0
                return piece.range.lowerBound + fraction * (piece.range.upperBound - piece.range.lowerBound)
            }
            remaining -= piece.share
        }
        return pieces.last?.range.upperBound ?? 0
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
