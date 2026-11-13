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

        // "A new fantastic" (weights 1, 1, 3) over a 4 s line voiced at 0.5–1.5 and 2.0–3.0:
        // the words share the 2 s of voice, not the whole line.
        let pitch = [note(62, 0.5, 1.5), note(64, 2.0, 2.4), note(65, 2.4, 3.0), note(50, 6, 7)]
        let line = useCase.execute(pitchNotes: pitch, lines: [.init(start: 0, end: 4, wordWeights: [1, 1, 3])])
        try check(line.notes.count == 3, "One note per word, got \(line.notes.count).")
        try check(line.words[0].allSatisfy { $0.note != nil }, "Every sung word has a note.")
        let (a, new, fantastic) = (line.words[0][0], line.words[0][1], line.words[0][2])
        try check(near(a.start, 0.5) && near(a.end, 0.9), "First word starts where the voice does: \(a).")
        try check(near(new.start, 0.9) && near(new.end, 1.3), "Second word follows by its weight: \(new).")
        try check(near(fantastic.start, 1.3) && near(fantastic.end, 3.0), "Long word spans the gap to the next voice: \(fantastic).")
        try check(a.note?.midiNote == 62 && fantastic.note?.midiNote == 65, "Each word takes the pitch held longest.")
        try check(!line.notes.contains { $0.midiNote == 50 }, "Pitch notes outside the lyrics are left out.")

        // A word ending exactly at a gap stays in the earlier voiced part; the next starts after it.
        let gap = useCase.execute(pitchNotes: [note(60, 0, 1), note(62, 2, 3)],
                                  lines: [.init(start: 0, end: 3, wordWeights: [1, 1])])
        try check(near(gap.words[0][0].end, 1) && near(gap.words[0][1].start, 2), "Words split at the gap: \(gap.words[0]).")

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

        // An octave error (80 in a line around 64–66) is folded back toward the line; a sixth is kept.
        let octave = useCase.execute(pitchNotes: [note(64, 0, 1), note(66, 1, 2), note(80, 2, 3), note(65, 3, 4)],
                                     lines: [.init(start: 0, end: 4, wordWeights: [1, 1, 1, 1])])
        try check(octave.notes.map(\.midiNote) == [64, 66, 68, 65], "Octave error folded: \(octave.notes.map(\.midiNote)).")
        let leap = useCase.execute(pitchNotes: [note(60, 0, 1), note(60, 1, 2), note(69, 2, 3)],
                                   lines: [.init(start: 0, end: 3, wordWeights: [1, 1, 1])])
        try check(leap.notes.map(\.midiNote) == [60, 60, 69], "A sixth leap is a real melody change.")

        // The guide's notes are the words' notes, in order.
        try check(line.notes.map(\.id) == line.words.flatMap { $0.compactMap(\.note?.id) }, "Notes match the words.")
        return count
    }
}
