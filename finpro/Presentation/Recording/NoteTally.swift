//
//  NoteTally.swift
//  finpro
//
//  How one guide note was sung so far, for its colour on the pitch guide (display only; the clip
//  score is EvaluateSegmentUseCase and keeps its own rules). A note turns one colour as a whole:
//  green when at least 65% of the moments with voice were within ±100 cents, or when its median
//  pitch was within ±75 cents (so stray misread moments, wide vibrato or a little song leaking
//  from the speaker cannot turn a well-sung note red); red otherwise.
//  Moments without voice (a breath, a consonant) do not count, but a note that was hardly sung
//  at all is red once it is over.
//

import Foundation

nonisolated struct NoteTally: Equatable, Sendable {
    enum Verdict: Equatable { case undecided, good, bad }

    /// Share of voiced moments that must be in tune for green.
    static let passShare: Float = 0.65
    /// Wider than the score's ±80 cents: colours encourage, the score decides retakes.
    static let toleranceCents: Float = 100
    /// A finished note sung for less than this share of its moments is red.
    static let minimumVoicedShare: Float = 0.3
    /// While the note is being sung, it stays grey until this many voiced moments were heard.
    static let minimumLiveFrames = 4
    /// A note whose median pitch is this close is green whatever the share.
    static let medianToleranceCents: Float = 75

    private(set) var total = 0
    private(set) var voiced = 0
    private(set) var inTune = 0
    private var deviations: [Float] = []

    /// - Parameter centDeviation: distance from the note (octave folded), nil without voice.
    mutating func add(centDeviation: Float?) {
        total += 1
        guard let centDeviation, centDeviation.isFinite else { return }
        voiced += 1
        deviations.append(centDeviation)
        if abs(centDeviation) <= Self.toleranceCents { inTune += 1 }
    }

    /// A moment sung right just outside the note (early or late, see NoteColoring): it helps
    /// the note but never counts against it.
    mutating func credit(centDeviation: Float) {
        voiced += 1
        inTune += 1
        deviations.append(centDeviation)
    }

    func verdict(finished: Bool) -> Verdict {
        if !finished {
            guard voiced >= Self.minimumLiveFrames else { return .undecided }
            return isSungRight ? .good : .bad
        }
        // A note shorter than its attack only has early/late moments to judge it by.
        guard total > 0 || voiced > 0 else { return .undecided }
        guard voiced > 0, Float(voiced) / Float(max(total, 1)) >= Self.minimumVoicedShare else { return .bad }
        return isSungRight ? .good : .bad
    }

    private var share: Float { Float(inTune) / Float(max(1, voiced)) }

    /// For the event log: "green, 19 moments in the note, 23 with voice (incl. early/late), 100% in tune, median 0 c".
    var summary: String {
        let verdict = switch verdict(finished: true) { case .good: "green"; case .bad: "red"; case .undecided: "grey" }
        let median = deviations.isEmpty ? "-" : "\(Int(deviations.sorted()[deviations.count / 2].rounded())) c"
        return "\(verdict), \(total) moments in the note, \(voiced) with voice (incl. early/late), \(Int((share * 100).rounded()))% in tune, median \(median)"
    }

    private var isSungRight: Bool {
        if share >= Self.passShare { return true }
        guard deviations.count >= 3 else { return false }
        return abs(deviations.sorted()[deviations.count / 2]) <= Self.medianToleranceCents
    }
}
