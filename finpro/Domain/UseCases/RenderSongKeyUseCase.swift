//
//  RenderSongKeyUseCase.swift
//  finpro
//

import Foundation

/// Render both tracks with the same shift, always starting from untransposed stems.
nonisolated struct RenderSongKeyUseCase: Sendable {
    let transposition: any AudioTranspositionRepository
    func execute(base: PreparedSong, stems: SeparatedStems, semitones: Int) async throws -> PreparedSong {
        guard TranspositionPlan.semitoneRange.contains(semitones) else {
            throw ContractViolation(contract: "Transposition", message: "Unsupported semitone shift.")
        }
        let mix = try await transposition.renderTransposed(stems.mixURL, semitones: semitones)
        try Task.checkCancellation()
        let instrumental = try await transposition.renderTransposed(stems.instrumentalURL, semitones: semitones)
        try Task.checkCancellation()
        let song = PreparedSong(earphoneMixURL: mix, instrumentalURL: instrumental, segments: base.segments,
                                transposition: .init(octaveShift: 0, semitoneShift: semitones),
                                duration: base.duration, separationMethod: base.separationMethod)
        if let error = song.validate().first { throw error }
        return song
    }
}
