//
//  NoteColoring.swift
//  finpro
//
//  Feeds live pitch into each guide note's NoteTally (display only; the clip score is separate).
//  Real singers are forgiving-worthy in three ways the strict per-moment match was not:
//  - they come in a little late (reaction and earphone latency) and sometimes early, so a note
//    also gets credit for being sung right just before it starts or just after it ends;
//  - they glide into a note, so its first moments (attack) do not count against it;
//  - the pitch tracker misreads single moments, so a moment is judged on the median of the
//    last three voiced moments.
//  Moments sung right count for every note they match within its window; moments that miss
//  count against a note only inside the note itself.
//

import Foundation

nonisolated struct NoteColoring: Sendable {
    struct GuideNote: Sendable {
        let id: UUID
        let start: TimeInterval
        let end: TimeInterval
        /// As the user should sing it (transposed).
        let midi: Float
    }

    /// Sung right this long before a note starts still counts for it.
    static let earlyGrace: TimeInterval = 0.1
    /// Sung right this long after a note ends still counts for it (coming in late).
    static let lateGrace: TimeInterval = 0.3
    /// The first moments of a note, gliding into it, never count against it.
    static let attack: TimeInterval = 0.15

    private let notes: [GuideNote]
    private(set) var tallies: [UUID: NoteTally] = [:]
    private var recent: [Float] = []
    private var lastVoiced: TimeInterval?

    init(notes: [GuideNote]) {
        self.notes = notes.sorted { $0.start < $1.start }
    }

    /// One live pitch moment on the song timeline; `midi` is nil without voice.
    mutating func add(time: TimeInterval, midi raw: Float?) {
        var midi: Float?
        if let raw, raw.isFinite {
            if let lastVoiced, time - lastVoiced > 0.25 { recent.removeAll() }
            recent.append(raw)
            if recent.count > 3 { recent.removeFirst() }
            midi = recent.sorted()[recent.count / 2]
            lastVoiced = time
        }
        for note in notes where time >= note.start - Self.earlyGrace && time < note.end + Self.lateGrace {
            let deviation = midi.map { Self.octaveFolded($0 - note.midi) * 100 }
            let inTune = deviation.map { abs($0) <= NoteTally.toleranceCents } ?? false
            let inside = time >= note.start + Self.attack && time < note.end
            if inside {
                tallies[note.id, default: NoteTally()].add(centDeviation: deviation)
            } else if inTune, let deviation {
                tallies[note.id, default: NoteTally()].credit(centDeviation: deviation)
            }
        }
    }

    mutating func reset() {
        tallies.removeAll()
        recent.removeAll()
        lastVoiced = nil
    }

    /// Semitone difference reduced to the nearest octave: −6 … +6 (singing an octave off is fine).
    static func octaveFolded(_ semitones: Float) -> Float {
        semitones - 12 * (semitones / 12).rounded()
    }
}
