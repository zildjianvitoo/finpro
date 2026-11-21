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
    /// (its syllable count), in order; `words` is the words' text (matched against recognized
    /// words; empty when unknown).
    struct Line: Sendable, Equatable {
        let start: TimeInterval
        let end: TimeInterval
        let wordWeights: [Double]
        let words: [String]

        init(start: TimeInterval, end: TimeInterval, wordWeights: [Double], words: [String] = []) {
            self.start = start
            self.end = end
            self.wordWeights = wordWeights
            self.words = words
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
    /// Leading silence kept before a line's first voiced note (enough for a consonant attack,
    /// without dumping the first word into half a second of silence before the singer enters).
    static let leadingAttackMargin: TimeInterval = 0.15
    /// Hold a word's note to the next word when the breath/gap between them is at most this long;
    /// longer pauses end the note where the voice stops instead of stretching across silence.
    static let maximumBreathHold: TimeInterval = 0.25
    /// Silent gap inside a single word beyond which a trailing voiced blip is treated as bleed
    /// rather than part of the same held note.
    static let bleedGapThreshold: TimeInterval = 0.45

    // Recognized words (on-device speech recognition of the vocal stem).
    /// A line's words are matched against the words recognized from this long before its first
    /// word to this long after the next line's first word.
    static let recognitionMargin: TimeInterval = 1.5
    /// A match that would move a word further than this is ignored: it is the same word sung
    /// elsewhere (a backing vocal in brackets, a repeat), not this one.
    static let maximumAnchorMove: TimeInterval = 3
    /// Shortest duration preserved for a line's last word when trimming its estimated tail to make
    /// room for an anchored next line.
    static let minimumWordDuration: TimeInterval = 0.15

    /// `pitchNotes`: the notes found in the vocal guide (original key), any order. `recognized`:
    /// words heard in the vocal stem; a lyric word matched to one starts where it was heard, and
    /// the words between two matches keep their spacing in between (measured on two English songs:
    /// words within 0.3 s 65% → 74% and 73% → 86%).
    func execute(pitchNotes: [TargetMIDINote], lines: [Line], recognized: [RecognizedWord] = []) -> Result {
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
        if !recognized.isEmpty {
            words = anchored(words, texts: lines.map(\.words), recognized: recognized, pitched: pitched)
            notes = words.flatMap { $0.compactMap(\.note) }
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

    /// Moves each line's words onto the recognized words that match them (in order, near the line);
    /// words between two matches keep their spacing, words before the first or after the last match
    /// move with it. Recognized `endTime` is preserved so trailing words and line endings don't
    /// collapse to zero or stretch across pauses and delay the next line.
    private func anchored(_ words: [[Word]], texts: [[String]], recognized: [RecognizedWord],
                          pitched: [TargetMIDINote]) -> [[Word]] {
        struct HeardToken {
            let index: Int
            let text: String
            let start: TimeInterval
            let end: TimeInterval
        }
        var rawHeard: [(text: String, start: TimeInterval, end: TimeInterval)] = []
        for word in recognized {
            let parts = word.text.split(whereSeparator: \.isWhitespace)
                .map { Self.normalized(String($0)) }
                .filter { !$0.isEmpty }
            guard !parts.isEmpty else { continue }
            let wordEnd = max(word.endTime, word.startTime)
            let step = (wordEnd - word.startTime) / Double(parts.count)
            for (idx, part) in parts.enumerated() {
                rawHeard.append((part, word.startTime + Double(idx) * step, word.startTime + Double(idx + 1) * step))
            }
        }
        rawHeard.sort { $0.start < $1.start }
        let heard = rawHeard.enumerated().map { HeardToken(index: $0.offset, text: $0.element.text, start: $0.element.start, end: $0.element.end) }

        var result = words
        var previousEnd = -TimeInterval.infinity
        var previousLastWordStart = -TimeInterval.infinity
        var previousWasAnchored = false
        var lastUsedHeardIndex = -1

        for index in words.indices {
            let line = words[index]
            guard let first = line.first, let last = line.last, texts[index].count == line.count else {
                result[index] = clampedAfter(previousEnd, line: line)
                if let lastWord = result[index].last {
                    previousEnd = max(previousEnd, lastWord.end)
                    previousLastWordStart = max(previousLastWordStart, lastWord.start)
                }
                previousWasAnchored = false
                continue
            }
            let nextStart = words[(index + 1)...].first { !$0.isEmpty }?.first?.start ?? last.end
            let window = (first.start - Self.recognitionMargin)...(max(nextStart, last.end, first.start) + Self.recognitionMargin)
            // Only consider tokens strictly after any token already matched by an earlier line.
            // An anchored previous line's held note may be trimmed by at most 0.35 s so a pause-
            // absorbing token on the next line (e.g. "you" starting where "are" is still held)
            // doesn't cut into the previous line; an unanchored previous line's estimated tail can
            // yield back to its last word's minimum duration.
            let minWordFloor = previousLastWordStart.isFinite
                ? previousLastWordStart + Self.minimumWordDuration
                : -TimeInterval.infinity
            let candidateFloor = (previousWasAnchored && previousEnd.isFinite)
                ? max(minWordFloor, previousEnd - 0.35)
                : minWordFloor
            let candidates = heard.filter {
                $0.index > lastUsedHeardIndex && window.contains($0.start) && $0.start >= candidateFloor
            }
            var anchors: [Int: (start: TimeInterval, end: TimeInterval, tokenIndex: Int)] = [:]
            var lastAnchor = -TimeInterval.infinity
            var highestHeardIndex = lastUsedHeardIndex
            for (word, candidateIdx) in Self.commonSubsequence(texts[index].map(Self.normalized), candidates.map(\.text)) {
                let token = candidates[candidateIdx]
                // In order only: a later lyric word never starts before an earlier one.
                if token.start > lastAnchor, abs(token.start - line[word].start) <= Self.maximumAnchorMove {
                    anchors[word] = (token.start, max(token.end, token.start), token.index)
                    lastAnchor = token.start
                    highestHeardIndex = max(highestHeardIndex, token.index)
                }
            }
            guard !anchors.isEmpty else {
                result[index] = clampedAfter(previousEnd, line: line)
                if let lastWord = result[index].last {
                    previousEnd = max(previousEnd, lastWord.end)
                    previousLastWordStart = max(previousLastWordStart, lastWord.start)
                }
                previousWasAnchored = false
                continue
            }
            lastUsedHeardIndex = highestHeardIndex
            let starts = line.map(\.start)
            var moved = starts
            let keys = anchors.keys.sorted()
            for key in keys { moved[key] = anchors[key]!.start }
            let leading = anchors[keys[0]]!.start - starts[keys[0]]
            for word in 0..<keys[0] { moved[word] = starts[word] + leading }
            let lastKey = keys[keys.count - 1]
            if lastKey + 1 < line.count {
                let anchor = anchors[lastKey]!
                let nextOriginal = starts[lastKey + 1]
                let expectedNext = max(anchor.end, anchor.start + Self.minimumWordDuration)
                let shiftedNext = nextOriginal + (anchor.start - starts[lastKey])
                // Don't let an over-stretched unanchored gap push trailing words past anchor.end.
                let trailingShift = min(shiftedNext, expectedNext) - nextOriginal
                for word in (lastKey + 1)..<line.count { moved[word] = starts[word] + trailingShift }
            }
            for (a, b) in zip(keys, keys.dropFirst()) where b > a + 1 {
                for word in (a + 1)..<b {
                    let fraction = starts[b] > starts[a] ? (starts[word] - starts[a]) / (starts[b] - starts[a]) : 0
                    moved[word] = anchors[a]!.start + fraction * (anchors[b]!.start - anchors[a]!.start)
                }
            }
            // If this anchored line genuinely starts slightly before the previous line's estimated
            // tail, trim the previous line's tail back instead of delaying this line.
            if index > 0, previousEnd.isFinite, moved[0] < previousEnd,
               moved[0] >= candidateFloor {
                result[index - 1] = trimmedBefore(moved[0], line: result[index - 1])
                previousEnd = moved[0]
            }
            // Forwards only, and never back into the previous line.
            for word in moved.indices {
                moved[word] = max(moved[word], previousEnd, word > 0 ? moved[word - 1] : -TimeInterval.infinity)
            }
            let lastWordStart = moved[moved.count - 1]
            let originalLastDuration = max(last.end - last.start, Self.minimumNoteLength)
            let hasNextLine = words[(index + 1)...].contains { !$0.isEmpty }
            let nextLineCeiling: TimeInterval
            if !hasNextLine {
                nextLineCeiling = .infinity
            } else if nextStart > lastWordStart + Self.minimumWordDuration {
                nextLineCeiling = nextStart
            } else {
                // This line's last word moved past the next line's shifted start (e.g. overlapping duet):
                // give the last word a realistic hold without swallowing the entire next line.
                nextLineCeiling = lastWordStart + max(originalLastDuration, 0.8)
            }
            let lineEnd: TimeInterval
            if let lastAnchor = anchors[line.count - 1] {
                var searchCap = min(max(last.end, lastAnchor.end), nextLineCeiling)
                if lastAnchor.tokenIndex + 1 < heard.count {
                    let nextToken = heard[lastAnchor.tokenIndex + 1]
                    if nextToken.end - nextToken.start <= 1.5, nextToken.start >= lastAnchor.end - Self.epsilon {
                        searchCap = min(searchCap, nextToken.start)
                    }
                }
                let cappedAnchorEnd = min(lastAnchor.end, searchCap)
                let voiceEnd = Self.contiguousVoicedEnd(from: lastWordStart, anchorEnd: cappedAnchorEnd, in: pitched, upTo: searchCap)
                lineEnd = max(cappedAnchorEnd, voiceEnd, lastWordStart + Self.minimumWordDuration)
            } else {
                let baseEnd = min(max(last.end, lastWordStart + originalLastDuration), nextLineCeiling)
                let voiceEnd = Self.contiguousVoicedEnd(from: lastWordStart, anchorEnd: min(lastWordStart + originalLastDuration, baseEnd), in: pitched, upTo: baseEnd)
                lineEnd = max(voiceEnd, lastWordStart + Self.minimumWordDuration)
            }
            let voiced = pitched.compactMap { note -> ClosedRange<TimeInterval>? in
                let lower = max(note.startTime, moved[0]), upper = min(note.endTime, lineEnd)
                return upper - lower > Self.epsilon ? lower...upper : nil
            }
            result[index] = moved.indices.map { word in
                let from = moved[word]
                let to = word + 1 < moved.count ? moved[word + 1] : lineEnd
                let anchorEnd = anchors[word]?.end
                return Word(start: from, end: to, note: noteFor(from: from, to: to, voiced: voiced, pitched: pitched, anchorEnd: anchorEnd))
            }
            previousEnd = lineEnd
            previousLastWordStart = lastWordStart
            previousWasAnchored = true
        }
        return result
    }

    /// Trims a previous line's trailing word/note end back to `ceiling` when the next line's
    /// recognized onset proves the previous line ended earlier than estimated.
    private func trimmedBefore(_ ceiling: TimeInterval, line: [Word]) -> [Word] {
        line.map { word in
            let end = min(word.end, max(word.start, ceiling))
            let trimmedNote: TargetMIDINote?
            if let note = word.note {
                let noteEnd = min(note.endTime, ceiling)
                let duration = noteEnd - note.startTime
                trimmedNote = duration > Self.epsilon
                    ? TargetMIDINote(id: note.id, midiNote: note.midiNote, startTime: note.startTime, duration: duration)
                    : nil
            } else {
                trimmedNote = nil
            }
            return Word(start: word.start, end: end, note: trimmedNote)
        }
    }

    /// Follows contiguous CREPE voiced notes from `start` (and through `anchorEnd`), stopping
    /// before any silent gap longer than `bleedGapThreshold` so stray bleed in a rest isn't eaten.
    private static func contiguousVoicedEnd(from start: TimeInterval, anchorEnd: TimeInterval,
                                            in pitched: [TargetMIDINote], upTo limit: TimeInterval) -> TimeInterval {
        var end = max(start, anchorEnd)
        var foundVoice = false
        for note in pitched {
            if note.endTime <= start + Self.epsilon { continue }
            if note.startTime >= limit { break }
            let clippedEnd = min(note.endTime, limit)
            if !foundVoice {
                if note.startTime - end > Self.bleedGapThreshold { break }
                foundVoice = true
                end = max(end, clippedEnd)
            } else {
                if note.startTime - end > Self.bleedGapThreshold { break }
                end = max(end, clippedEnd)
            }
        }
        return end
    }

    /// Keeps an unanchored line from overlapping a previous line that recognition moved later.
    private func clampedAfter(_ floor: TimeInterval, line: [Word]) -> [Word] {
        guard floor.isFinite, let first = line.first, first.start < floor else { return line }
        var cursor = floor
        return line.map { word in
            let start = max(word.start, cursor)
            let end = max(start, word.end)
            cursor = end
            let trimmedNote: TargetMIDINote?
            if let note = word.note {
                let noteStart = max(note.startTime, start)
                let noteEnd = max(noteStart, note.endTime)
                let duration = noteEnd - noteStart
                trimmedNote = duration > Self.epsilon
                    ? TargetMIDINote(id: note.id, midiNote: note.midiNote, startTime: noteStart, duration: duration)
                    : nil
            } else {
                trimmedNote = nil
            }
            return Word(start: start, end: end, note: trimmedNote)
        }
    }

    /// Lower-case letters and digits only, so "you're" matches "youre" and "Part," matches "part".
    static func normalized(_ word: String) -> String {
        String(word.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// Index pairs of a longest common subsequence of `a` and `b`, in order.
    static func commonSubsequence(_ a: [String], _ b: [String]) -> [(Int, Int)] {
        guard !a.isEmpty, !b.isEmpty else { return [] }
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var pairs: [(Int, Int)] = []
        var i = 0, j = 0
        while i < a.count && j < b.count {
            if a[i] == b[j] {
                pairs.append((i, j))
                i += 1
                j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return pairs
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
        // From just before the line's first voice (keeping a brief consonant margin) to its last
        // voiced moment: silent and voiced parts, each counting only up to its cap.
        var pieces: [Piece] = []
        var time = voiced.first.map { max(start, $0.lowerBound - Self.leadingAttackMargin) } ?? start
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
                         pitched: [TargetMIDINote], anchorEnd: TimeInterval? = nil) -> TargetMIDINote? {
        guard to - from > Self.epsilon else { return nil }
        let inside = voiced.compactMap { part -> ClosedRange<TimeInterval>? in
            let lower = max(part.lowerBound, from), upper = min(part.upperBound, to)
            return upper - lower > Self.epsilon ? lower...upper : nil
        }
        if let first = inside.first,
           let midi = dominantPitch(from: from, to: to, in: pitched) {
            // Follow contiguous voiced parts of this word, stopping before a long silent gap
            // so stray bleed later in a breath doesn't stretch the note bar across silence.
            var clusterEnd = first.upperBound
            for part in inside.dropFirst() {
                let withinAnchor = anchorEnd.map { part.lowerBound <= $0 + Self.epsilon } ?? false
                if part.lowerBound - clusterEnd <= Self.bleedGapThreshold || withinAnchor {
                    clusterEnd = max(clusterEnd, part.upperBound)
                } else {
                    break
                }
            }
            // Long enough to be seen and sung: grown around the voice, inside the word.
            let length = min(max(clusterEnd - first.lowerBound, Self.minimumNoteLength), to - from)
            let middle = (first.lowerBound + clusterEnd) / 2
            let start = min(max(middle - length / 2, from), to - length)
            let voicedEnd = min(to, max(clusterEnd, anchorEnd ?? 0, start + length))
            // Hold seamlessly to the next word when words flow together; end at the voice when a
            // clear breath or pause (> maximumBreathHold) follows.
            let end = (to - voicedEnd > Self.maximumBreathHold) ? voicedEnd : to
            return TargetMIDINote(midiNote: midi, startTime: start, duration: end - start)
        }
        return nearestPitch(to: from, in: voiced, pitched: pitched).map { midi in
            let end: TimeInterval
            if let anchorEnd {
                let natural = min(to, max(anchorEnd, from + Self.minimumNoteLength))
                end = (to - natural > Self.maximumBreathHold) ? natural : to
            } else {
                end = to
            }
            return TargetMIDINote(midiNote: midi, startTime: from, duration: end - from)
        }
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
