//
//  RenderSongKeyUseCase.swift
//  finpro
//

import Foundation

/// Render both tracks with the same shift, always starting from untransposed stems.
nonisolated struct RenderSongKeyUseCase: Sendable {
    let transposition: any AudioTranspositionRepository
    func execute(base: PreparedSong, stems: SeparatedStems, semitones: Int,
                 leadIn: PrepareSongUseCase.LeadInStems? = nil) async throws -> PreparedSong {
        guard TranspositionPlan.semitoneRange.contains(semitones) else {
            throw ContractViolation(contract: "Transposition", message: "Unsupported semitone shift.")
        }
        let mix = try await transposition.renderTransposed(stems.mixURL, semitones: semitones)
        try Task.checkCancellation()
        let instrumental = try await transposition.renderTransposed(stems.instrumentalURL, semitones: semitones)
        try Task.checkCancellation()
        var song = PreparedSong(earphoneMixURL: mix, instrumentalURL: instrumental, segments: base.segments,
                                transposition: .init(octaveShift: 0, semitoneShift: semitones),
                                duration: base.duration, separationMethod: base.separationMethod)
        song.leadIn = await PrepareSongUseCase.renderLeadIn(leadIn, semitones: semitones, transposition: transposition)
        try Task.checkCancellation()
        if let error = song.validate().first { throw error }
        return song
    }
}
