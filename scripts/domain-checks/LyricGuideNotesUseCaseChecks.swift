//
//  LyricGuideNotesUseCaseChecks.swift
//  finpro
//
//  Executable checks for LyricGuideNotesUseCase (pitch guide built from the lyrics, one note per
//  word). Not part of the app target.
//

import Foundation

nonisolated enum LyricGuideNotesUseCaseChecks {
    static func run() throws -> Int {
        var count = 0
        func check(_ condition: Bool, _ message: String) throws {
            count += 1
            if !condition { throw ContractViolation(contract: "LyricGuideNotesUseCase", message: message) }
        }
        func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= 1e-6 }
        func note(_ midi: Int, _ start: Double, _ end: Double) -> TargetMIDINote {
            TargetMIDINote(midiNote: midi, startTime: start, duration: end - start)
        }
        let useCase = LyricGuideNotesUseCase()

        // "A new fantastic" (weights 1, 1, 3) over a 4 s line voiced at 0.5–1.5 and 2.0–3.0.
        // Leading silence is capped at leadingAttackMargin (0.15 s -> starts at 0.35), so the
        // first word isn't dumped into 0.5 s of silence before the voice enters.
        let pitch = [note(62, 0.5, 1.5), note(64, 2.0, 2.4), note(65, 2.4, 3.0), note(50, 6, 7)]
        let line = useCase.execute(pitchNotes: pitch, lines: [.init(start: 0, end: 4, wordWeights: [1, 1, 3])])
        try check(line.notes.count == 3, "One note per word, got \(line.notes.count).")
        try check(line.words[0].allSatisfy { $0.note != nil }, "Every sung word has a note.")
        let (a, new, fantastic) = (line.words[0][0], line.words[0][1], line.words[0][2])
        try check(near(a.start, 0.5 - LyricGuideNotesUseCase.leadingAttackMargin) && a.end > 0.5,
                  "First word trims excessive leading silence and reaches the voice: \(a).")
        try check(near(new.start, a.end) && new.end > new.start, "Second word follows by its weight: \(new).")
        try check(near(fantastic.start, new.end) && near(fantastic.end, 3.0), "Last word ends with the last voice: \(fantastic).")
        try check(a.note?.midiNote == 62, "First word gets the pitch of the line's first voice.")
        try check(fantastic.note?.midiNote == 65, "Each word takes the pitch held longest.")
        try check(!line.notes.contains { $0.midiNote == 50 }, "Pitch notes outside the lyrics are left out.")
        try check(line.lineShift == 0, "One line is too few to move the lines.")

        // A soft unvoiced word between voiced parts still gets a note with the nearest pitch.
        let soft = useCase.execute(pitchNotes: [note(62, 0, 0.2), note(64, 0.8, 1.4)],
                                   lines: [.init(start: 0, end: 1.4, wordWeights: [1, 1, 1])])
        try check(soft.notes.count == 3, "Unvoiced middle word still gets a note: \(soft.words[0]).")

        // A long held last word ("…how far") no longer pushes the words before it late: each word
        // starts on its own short note, not a quarter of the way into the voiced time.
        let held = useCase.execute(pitchNotes: [note(60, 0, 0.2), note(62, 0.25, 0.45), note(64, 0.5, 0.7), note(65, 0.75, 3.75)],
                                   lines: [.init(start: 0, end: 4, wordWeights: [1, 1, 1, 1])])
        for (word, sung) in zip(held.words[0], [0, 0.25, 0.5, 0.75]) {
            try check(abs(word.start - sung) <= 0.05, "Held note: word starts near its note at \(sung): \(held.words[0]).")
        }
        try check(near(held.words[0][3].end, 3.75) && held.words[0][3].note?.midiNote == 65, "The held word keeps its long note.")

        // The tracker heard only the tail of a word: its note grows to a length that can be sung,
        // around that voice and inside the word, stopping before a clear breath (> maximumBreathHold).
        let tail = useCase.execute(pitchNotes: [note(60, 0.95, 1.0), note(62, 2, 3)],
                                   lines: [.init(start: 0, end: 3, wordWeights: [1, 1])])
        if let short = tail.words[0][0].note {
            try check(short.duration >= LyricGuideNotesUseCase.minimumNoteLength - 1e-9
                      && short.startTime >= tail.words[0][0].start - 1e-9
                      && short.endTime <= tail.words[0][0].end + 1e-9
                      && short.endTime < 1.3, "A short note grows around the voice without stretching across a breath: \(short).")
        } else { try check(false, "The first word has a note.") }

        // A long rest is split between the words around it; the first note ends at its voice instead
        // of stretching across the breath (> maximumBreathHold), and the next starts at its voice.
        let gap = useCase.execute(pitchNotes: [note(60, 0, 1), note(62, 2, 3)],
                                  lines: [.init(start: 0, end: 3, wordWeights: [1, 1])])
        try check(gap.words[0][0].end >= 1 && gap.words[0][1].start <= 2, "Words meet inside the rest: \(gap.words[0]).")
        try check(gap.words[0].map { $0.note?.midiNote } == [60, 62], "Each word keeps the pitch it covers.")
        let gapNotes = gap.words[0].compactMap(\.note)
        try check(gapNotes.count == 2 && near(gapNotes[0].endTime, 1.0) && near(gapNotes[1].startTime, 2.0),
                  "A note stops at its voice before a long rest; the next starts at its own voice: \(gapNotes).")

        // Short consonant gap (<= maximumBreathHold) still holds seamlessly to the next word.
        let tight = useCase.execute(pitchNotes: [note(60, 0, 0.4), note(64, 0.55, 1.0)],
                                    lines: [.init(start: 0, end: 1.0, wordWeights: [1, 1], words: ["bolehkah", "ku"])],
                                    recognized: [RecognizedWord(text: "bolehkah", startTime: 0, endTime: 0.4),
                                                 RecognizedWord(text: "ku", startTime: 0.55, endTime: 1.0)])
        try check(tight.notes.count == 2 && near(tight.notes[0].endTime, 0.55),
                  "Short gap (<= maximumBreathHold) holds seamlessly to the next word: \(tight.notes).")

        // Synced lyrics 1 s early for this recording: the lines move onto the sung phrases, starting
        // the attack lead before the pitch tracker's first note.
        let early = useCase.execute(pitchNotes: [note(60, 1, 2), note(62, 5, 6), note(64, 9, 10), note(65, 13, 14)],
                                    lines: (0..<4).map { .init(start: Double($0) * 4, end: Double($0) * 4 + 4, wordWeights: [1]) })
        try check(abs(early.lineShift - (1 - LyricGuideNotesUseCase.attackLead)) <= 1e-6, "Lines move 1 s minus the lead: \(early.lineShift).")
        try check(early.words.map { $0[0].note?.midiNote } == [60, 62, 64, 65], "Each line gets its own phrase.")

        // A line with no voice keeps its words (spread evenly) but gets no notes.
        let silent = useCase.execute(pitchNotes: [], lines: [.init(start: 0, end: 2, wordWeights: [1, 1])])
        try check(silent.notes.isEmpty && silent.words[0].count == 2 && near(silent.words[0][1].start, 1),
                  "Silent line: words spread, no notes.")

        // Overlapping lines still give a sorted, monophonic guide.
        let overlap = useCase.execute(pitchNotes: [note(60, 0, 2.5), note(62, 2.5, 5)],
                                      lines: [.init(start: 0, end: 3, wordWeights: [1]), .init(start: 2, end: 5, wordWeights: [1, 2])])
        for (previous, next) in zip(overlap.notes, overlap.notes.dropFirst()) {
            try check(previous.endTime <= next.startTime + 1e-9, "Notes must not overlap.")
        }

        // Overlapping pitch notes (never expected from the tracker) still give ordered, non-overlapping notes.
        let messy = useCase.execute(pitchNotes: [note(60, 0, 1.5), note(62, 1, 2), note(64, 1.8, 3)],
                                    lines: [.init(start: 0, end: 3, wordWeights: [1, 1, 1])])
        for (previous, next) in zip(messy.notes, messy.notes.dropFirst()) {
            try check(previous.endTime <= next.startTime + 1e-9, "Overlapping pitch notes: notes must not overlap: \(messy.notes).")
        }
        try check(messy.words[0].allSatisfy { $0.end >= $0.start }, "Overlapping pitch notes: words run forwards.")

        // An octave error (80 in a line around 64–66) is folded back toward the line; a sixth is kept.
        let octave = useCase.execute(pitchNotes: [note(64, 0, 1), note(66, 1, 2), note(80, 2, 3), note(65, 3, 4)],
                                     lines: [.init(start: 0, end: 4, wordWeights: [1, 1, 1, 1])])
        try check(octave.notes.map(\.midiNote) == [64, 66, 68, 65], "Octave error folded: \(octave.notes.map(\.midiNote)).")
        let leap = useCase.execute(pitchNotes: [note(60, 0, 1), note(60, 1, 2), note(69, 2, 3)],
                                   lines: [.init(start: 0, end: 3, wordWeights: [1, 1, 1])])
        try check(leap.notes.map(\.midiNote) == [60, 60, 69], "A sixth leap is a real melody change.")

        // An octave error that pulls its own short line up ("Or where to go": 76 among 69, 64, 61)
        // is caught against the words around it, across the line boundary.
        // The lines start the attack lead before the voice, as in a well synced song, so they stay put.
        let pitches = [66, 68, 68, 69, 76, 64, 61, 61]
        let lead = LyricGuideNotesUseCase.attackLead
        let neighbours = useCase.execute(
            pitchNotes: pitches.enumerated().map { note($1, Double($0), Double($0 + 1)) },
            lines: [.init(start: -lead, end: 3, wordWeights: [1, 1, 1]), .init(start: 3 - lead, end: 8, wordWeights: [1, 1, 1, 1, 1])])
        try check(abs(neighbours.lineShift) <= 1e-6, "A well synced song is not moved: \(neighbours.lineShift).")
        try check(neighbours.notes.map(\.midiNote) == [66, 68, 68, 69, 64, 64, 61, 61],
                  "Octave error folded against its neighbours: \(neighbours.notes.map(\.midiNote)).")

        // Recognized words (speech recognition of the vocal stem) anchor the words they match.
        let sung = [note(60, 0, 1), note(62, 1, 2), note(64, 2, 3), note(65, 3, 4)]
        let plain = useCase.execute(pitchNotes: sung, lines: [.init(start: 0, end: 4, wordWeights: [1, 1, 1, 1],
                                                                       words: ["Best", "part,", "of", "you"])])
        let heard = [RecognizedWord(text: "best", startTime: 0.1, endTime: 0.5),
                     RecognizedWord(text: "you", startTime: 3.2, endTime: 3.6)]
        let anchoredLine = useCase.execute(pitchNotes: sung, lines: [.init(start: 0, end: 4, wordWeights: [1, 1, 1, 1],
                                                                             words: ["Best", "part,", "of", "you"])],
                                           recognized: heard)
        try check(near(anchoredLine.words[0][0].start, 0.1) && near(anchoredLine.words[0][3].start, 3.2),
                  "Matched words start where they were heard: \(anchoredLine.words[0]).")
        let (p0, p3) = (plain.words[0][0].start, plain.words[0][3].start)
        let expected = 0.1 + (plain.words[0][1].start - p0) / (p3 - p0) * 3.1
        try check(abs(anchoredLine.words[0][1].start - expected) <= 1e-6, "Words between matches keep their spacing.")
        for (previous, next) in zip(anchoredLine.notes, anchoredLine.notes.dropFirst()) {
            try check(previous.endTime <= next.startTime + 1e-9, "Anchored notes must not overlap.")
        }
        let none = useCase.execute(pitchNotes: sung, lines: [.init(start: 0, end: 4, wordWeights: [1, 1, 1, 1],
                                                                      words: ["Best", "part,", "of", "you"])],
                                   recognized: [RecognizedWord(text: "you", startTime: 3.95 + LyricGuideNotesUseCase.maximumAnchorMove, endTime: 9)])
        try check(none.words[0].map { [$0.start, $0.end] } == plain.words[0].map { [$0.start, $0.end] },
                  "A match further than the maximum move is ignored.")

        // Recognized last word starting at/after the unanchored line end keeps its real duration
        // instead of collapsing to 0 s, and doesn't swallow the next line.
        let lateLast = useCase.execute(
            pitchNotes: [note(60, 0.0, 0.8), note(62, 1.0, 1.4), note(64, 1.5, 2.5)],
            lines: [
                .init(start: 0, end: 1.0, wordWeights: [1, 1], words: ["close", "eyes"]),
                .init(start: 1.0, end: 2.5, wordWeights: [1, 1], words: ["next", "line"]),
            ],
            recognized: [
                RecognizedWord(text: "close", startTime: 0.0, endTime: 0.8),
                RecognizedWord(text: "eyes", startTime: 1.0, endTime: 1.4),
                RecognizedWord(text: "next", startTime: 1.5, endTime: 2.0),
                RecognizedWord(text: "line", startTime: 2.0, endTime: 2.5),
            ]
        )
        try check(lateLast.words[0][1].note.map { $0.duration >= 0.35 } == true,
                  "Last word anchored at old lineEnd never collapses to 0 s: \(lateLast.words[0][1]).")
        try check(lateLast.words[1][0].start >= lateLast.words[0][1].end - 1e-6 && near(lateLast.words[1][0].start, 1.5),
                  "Next line starts at its recognized onset without cascading delay: \(lateLast.words[1]).")

        // Stray vocal bleed after a long pause doesn't stretch a word across silence.
        let bleed = useCase.execute(
            pitchNotes: [note(60, 0.0, 0.8), note(64, 2.2, 2.4)],
            lines: [.init(start: 0, end: 3.0, wordWeights: [1], words: ["desire"])],
            recognized: [RecognizedWord(text: "desire", startTime: 0.0, endTime: 0.7)]
        )
        try check(bleed.notes.count == 1 && bleed.notes[0].endTime <= 0.9,
                  "Bleed after a long pause doesn't stretch the note: \(bleed.notes).")

        // The guide's notes are the words' notes, in order.
        try check(line.notes.map(\.id) == line.words.flatMap { $0.compactMap(\.note?.id) }, "Notes match the words.")
        return count
    }
}
