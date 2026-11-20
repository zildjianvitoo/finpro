//
//  RecommendKeysUseCase.swift
//  finpro
//

import Foundation

/// Extremes and duration-weighted distance from the center of the tested range. Keys whose melody
/// fits are returned (its brief extremes aside, `keyFitOutlierFraction`). When none fits, e.g. a
/// two-octave part for a 1.5-octave voice, the one best compromise is returned instead of nothing:
/// the least sung time outside the range, weighted by how far outside.
nonisolated struct RecommendKeysUseCase: Sendable {
    struct Recommendation: Sendable, Equatable {
        let plan: TranspositionPlan
        let penalty: Double
        let lowestMIDI: Int
        let highestMIDI: Int
        /// False for a compromise: some of the melody stays outside the tested range.
        var fitsRange = true
        /// Sung time outside the range × semitones outside, per second of melody (0 when it fits).
        var outsideCost: Double = 0
    }

    var configuration: AppConfiguration = .default

    func execute(notes: [TargetMIDINote], vocalRange: VocalRange) throws -> [Recommendation] {
        let low = Double(vocalRange.lowestMIDI), high = Double(vocalRange.highestMIDI)
        guard low.isFinite, high.isFinite, high > low else {
            throw ContractViolation(contract: "KeyRecommendations", message: "Invalid vocal range.")
        }
        guard !notes.isEmpty else { return [] }
        guard notes.allSatisfy({ (0...127).contains($0.midiNote) && $0.duration.isFinite && $0.duration > 0 }) else {
            throw ContractViolation(contract: "KeyRecommendations", message: "Invalid guide notes.")
        }
        let halfSpan = (high - low) / 2
        let extremesWeight = configuration.rangePenaltyExtremesWeight
        let totalDuration = notes.reduce(0) { $0 + $1.duration }
        guard halfSpan > 0, totalDuration.isFinite, (0...1).contains(extremesWeight) else {
            throw ContractViolation(contract: "KeyRecommendations", message: "Invalid scoring configuration.")
        }
        let core = coreRange(notes, totalDuration: totalDuration)
        // Audio and targets must use exactly the same shift. Target-only octave shifts
        // from the legacy planner are deliberately not candidates for this feature.
        let candidates = TranspositionPlan.semitoneRange.compactMap { shift -> Recommendation? in
            let pitches = notes.map { $0.midiNote + shift }
            guard pitches.allSatisfy({ (0...127).contains($0) }) else { return nil }
            func edgeCost(_ pitch: Int) -> Double {
                let distance = min(Double(pitch) - low, high - Double(pitch))
                let edge = max(0, 1 - distance / halfSpan)
                return edge * edge
            }
            func outside(_ pitch: Int) -> Double { max(0, low - Double(pitch), Double(pitch) - high) }
            let weighted = zip(notes, pitches).reduce(0.0) { $0 + edgeCost($1.1) * $1.0.duration } / totalDuration
            // Even a brief high/low note matters, and sustained notes still affect comfort.
            let extremes = (edgeCost(pitches.min()!) + edgeCost(pitches.max()!)) / 2
            let penalty = extremesWeight * extremes + (1 - extremesWeight) * weighted
            let fits = Double(core.lowerBound + shift) >= low && Double(core.upperBound + shift) <= high
            let outsideCost = zip(notes, pitches).reduce(0.0) { $0 + outside($1.1) * $1.0.duration } / totalDuration
            return Recommendation(plan: TranspositionPlan(octaveShift: 0, semitoneShift: shift),
                                  penalty: 100 * penalty,
                                  lowestMIDI: pitches.min()!, highestMIDI: pitches.max()!,
                                  fitsRange: fits, outsideCost: outsideCost)
        }
        func smallerShift(_ a: Recommendation, _ b: Recommendation) -> Bool {
            if abs(a.plan.semitoneShift) != abs(b.plan.semitoneShift) {
                return abs(a.plan.semitoneShift) < abs(b.plan.semitoneShift)
            }
            return a.plan.semitoneShift < b.plan.semitoneShift
        }
        let fitting = candidates.filter(\.fitsRange)
        if !fitting.isEmpty {
            return Array(fitting.sorted {
                if $0.penalty != $1.penalty { return $0.penalty < $1.penalty }
                return smallerShift($0, $1)
            }.prefix(configuration.keyRecommendationCount))
        }
        // Nothing fits: one compromise, the least singing outside the range.
        return candidates.min {
            if $0.outsideCost != $1.outsideCost { return $0.outsideCost < $1.outsideCost }
            if $0.penalty != $1.penalty { return $0.penalty < $1.penalty }
            return smallerShift($0, $1)
        }.map { [$0] } ?? []
    }

    /// The pitch range of the melody without its brief extremes: the lowest and highest pitch
    /// once `keyFitOutlierFraction` of the sung time is left out at each end.
    private func coreRange(_ notes: [TargetMIDINote], totalDuration: TimeInterval) -> ClosedRange<Int> {
        let sorted = notes.sorted { $0.midiNote < $1.midiNote }
        let cut = totalDuration * min(0.49, max(0, configuration.keyFitOutlierFraction))
        func pitch(after skipped: TimeInterval, in notes: [TargetMIDINote]) -> Int {
            var sum = 0.0
            for note in notes {
                sum += note.duration
                if sum > skipped + ContractTolerance.timeline { return note.midiNote }
            }
            return notes.last!.midiNote
        }
        let lowest = pitch(after: cut, in: sorted)
        let highest = pitch(after: cut, in: sorted.reversed())
        return min(lowest, highest)...max(lowest, highest)
    }

    /// A breath-delimited vocal phrase, including breathing room, in the trimmed song.
    /// Equal highest notes prefer the longest held occurrence, then the earliest.
    func highestPhrase(notes: [TargetMIDINote], duration: TimeInterval) -> ClosedRange<TimeInterval>? {
        let sorted = notes.sorted { $0.startTime < $1.startTime }
        guard duration.isFinite, duration > 0, let peak = sorted.max(by: {
            if $0.midiNote != $1.midiNote { return $0.midiNote < $1.midiNote }
            if $0.duration != $1.duration { return $0.duration < $1.duration }
            return $0.startTime > $1.startTime
        }), let index = sorted.firstIndex(where: { $0.id == peak.id }) else { return nil }
        var first = index, last = index
        while first > 0, sorted[first].startTime - sorted[first - 1].endTime <= configuration.segmentGap { first -= 1 }
        while last + 1 < sorted.count, sorted[last + 1].startTime - sorted[last].endTime <= configuration.segmentGap { last += 1 }
        let start = max(0, sorted[first].startTime - configuration.segmentGap / 2)
        let end = min(duration, sorted[last].endTime + configuration.segmentGap / 2)
        return end > start ? start...end : nil
    }
}
