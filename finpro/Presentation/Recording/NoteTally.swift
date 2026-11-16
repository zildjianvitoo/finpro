//
//  NoteTally.swift
//  finpro
//
//  How one guide note was sung so far, for its colour on the pitch guide (display only; the clip
//  score is EvaluateSegmentUseCase and keeps its own rules). A note turns one colour as a whole:
//  green when at least 65% of the moments with voice were within ±100 cents, red otherwise.
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

    private(set) var total = 0
    private(set) var voiced = 0
    private(set) var inTune = 0

    /// - Parameter centDeviation: distance from the note (octave folded), nil without voice.
    mutating func add(centDeviation: Float?) {
        total += 1
        guard let centDeviation, centDeviation.isFinite else { return }
        voiced += 1
        if abs(centDeviation) <= Self.toleranceCents { inTune += 1 }
    }

    func verdict(finished: Bool) -> Verdict {
        if !finished {
            guard voiced >= Self.minimumLiveFrames else { return .undecided }
            return share >= Self.passShare ? .good : .bad
        }
        guard total > 0 else { return .undecided }
        guard voiced > 0, Float(voiced) / Float(total) >= Self.minimumVoicedShare else { return .bad }
        return share >= Self.passShare ? .good : .bad
    }

    private var share: Float { Float(inTune) / Float(max(1, voiced)) }
}
