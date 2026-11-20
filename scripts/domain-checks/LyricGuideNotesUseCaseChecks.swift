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

        // "A new fantastic" (weights 1, 1, 3) over a 4 s line voiced at 0.5–1.5 and 2.0–3.0. A voiced
        // part counts 0.2 s and a silent one 0.5 s at most (1.6 in all), up to the last voice at 3.0.
        let pitch = [note(62, 0.5, 1.5), note(64, 2.0, 2.4), note(65, 2.4, 3.0), note(50, 6, 7)]
        let line = useCase.execute(pitchNotes: pitch, lines: [.init(start: 0, end: 4, wordWeights: [1, 1, 3])])
        try check(line.notes.count == 3, "One note per word, got \(line.notes.count).")
        try check(line.words[0].allSatisfy { $0.note != nil }, "Every sung word has a note.")
        let (a, new, fantastic) = (line.words[0][0], line.words[0][1], line.words[0][2])
        try check(near(a.start, 0) && near(a.end, 0.32), "First word starts with the line: \(a).")
        try check(near(new.start, 0.32) && near(new.end, 1.2), "Second word follows by its weight: \(new).")
        try check(near(fantastic.start, 1.2) && near(fantastic.end, 3.0), "Last word ends with the last voice: \(fantastic).")
        try check(a.note?.midiNote == 62 && a.note.map { near($0.startTime, 0) && near($0.endTime, 0.32) } == true,
                  "A word with no pitch heard (a soft first word) gets the nearest pitch of its line over its own time.")
        try check(new.note.map { near($0.startTime, 0.5) && near($0.endTime, 1.2) } == true,
                  "A note starts where its word's voice starts and is held to the word's end.")
        try check(fantastic.note?.midiNote == 65, "Each word takes the pitch held longest.")
        try check(!line.notes.contains { $0.midiNote == 50 }, "Pitch notes outside the lyrics are left out.")
        try check(line.lineShift == 0, "One line is too few to move the lines.")

        // A long held last word ("…how far") no longer pushes the words before it late: each word
        // starts on its own short note, not a quarter of the way into the voiced time.
        let held = useCase.execute(pitchNotes: [note(60, 0, 0.2), note(62, 0.25, 0.45), note(64, 0.5, 0.7), note(65, 0.75, 3.75)],
                                   lines: [.init(start: 0, end: 4, wordWeights: [1, 1, 1, 1])])
        for (word, sung) in zip(held.words[0], [0, 0.25, 0.5, 0.75]) {
            try check(abs(word.start - sung) <= 0.05, "Held note: word starts near its note at \(sung): \(held.words[0]).")
        }
        try check(near(held.words[0][3].end, 3.75) && held.words[0][3].note?.midiNote == 65, "The held word keeps its long note.")

        // The tracker heard only the tail of a word: its note grows to a length that can be sung,
        // around that voice and inside the word.
        let tail = useCase.execute(pitchNotes: [note(60, 0.95, 1.0), note(62, 2, 3)],
                                   lines: [.init(start: 0, end: 3, wordWeights: [1, 1])])
        if let short = tail.words[0][0].note {
            try check(short.duration >= LyricGuideNotesUseCase.minimumNoteLength - 1e-9 && short.startTime >= tail.words[0][0].start - 1e-9
                      && near(short.endTime, tail.words[0][0].end), "A short note grows inside its word: \(short).")
        } else { try check(false, "The first word has a note.") }

        // A long rest is split between the words around it, not given to one of them.
        let gap = useCase.execute(pitchNotes: [note(60, 0, 1), note(62, 2, 3)],
                                  lines: [.init(start: 0, end: 3, wordWeights: [1, 1])])
        try check(gap.words[0][0].end >= 1 && gap.words[0][1].start <= 2, "Words meet inside the rest: \(gap.words[0]).")
        try check(gap.words[0].map { $0.note?.midiNote } == [60, 62], "Each word keeps the pitch it covers.")
        let gapNotes = gap.words[0].compactMap(\.note)
        try check(gapNotes.count == 2 && near(gapNotes[0].endTime, gap.words[0][0].end) && near(gapNotes[1].startTime, 2),
                  "A note is held to its word's end; the next starts at its own voice, not in the rest: \(gapNotes).")

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

        // The guide's notes are the words' notes, in order.
        try check(line.notes.map(\.id) == line.words.flatMap { $0.compactMap(\.note?.id) }, "Notes match the words.")
        return count
    }
}
