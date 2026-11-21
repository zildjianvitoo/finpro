//
//  LeadInStemSeparation.swift
//  finpro
//
//  Optional separation capability: separates the trimmed part together with its pre-roll lead-in
//  in one model pass instead of running a second full window for the lead-in.
//

import Foundation

nonisolated protocol LeadInStemSeparation: StemSeparationRepository {
    func separateStems(from audioURL: URL, trimRange: ClosedRange<TimeInterval>,
                       leadInDuration: TimeInterval) async throws -> (stems: SeparatedStems, leadIn: SeparatedStems?)
}
