//
//  PrepareSongUseCase.swift
//  finpro
//

import Foundation

/// Orchestrates preparation using injected repositories; owns no media framework.
nonisolated struct PrepareSongUseCase: Sendable {
    let separation: any StemSeparationRepository
    let analysis: any AudioAnalysisRepository
    let fallbackAnalysis: (any AudioAnalysisRepository)?
    let transposition: any AudioTranspositionRepository
    var configuration: AppConfiguration = .default
    /// Hears the sung words in the vocal stem so the lyric guide puts them where they are sung;
    /// nil (or no words heard) places them from the pitch notes alone.
    var wordRecognition: (any SungWordRecognitionRepository)?

    func execute(audioURL: URL, trimRange: ClosedRange<TimeInterval>, vocalRange: VocalRange,
                 progress: @escaping @Sendable (String) -> Void = { _ in }) async throws -> PreparedSong {
        let (stems, extracted) = try await extract(audioURL: audioURL, trimRange: trimRange, progress: progress)
        // Fewer, longer blocks that a singer can follow (device feedback 2026-11-01).
        let notes = SimplifyGuideUseCase(configuration: configuration).execute(extracted)
        guard !notes.isEmpty else {
            throw ContractViolation(contract: "Preparation", message: "We couldn't find a vocal melody in this section. Try another part of the song.")
        }
        try Task.checkCancellation()
        progress("Building practice segments")
        let duration = trimRange.upperBound - trimRange.lowerBound
        let segments = try SliceSegmentsUseCase(configuration: configuration).execute(notes: notes, duration: duration)
        let plan = try ComputeTranspositionUseCase().execute(notes: notes, vocalRange: vocalRange)
        progress("Rendering the rehearsal key")
        // Octaves affect targets only. Both audio tracks receive the same semitone shift.
        let mix = try await transposition.renderTransposed(stems.mixURL, semitones: plan.semitoneShift)
        try Task.checkCancellation()
        let instrumental = try await transposition.renderTransposed(stems.instrumentalURL, semitones: plan.semitoneShift)
        try Task.checkCancellation()
        let song = PreparedSong(earphoneMixURL: mix, instrumentalURL: instrumental, segments: segments,
                                transposition: plan, duration: duration, separationMethod: stems.method)
        if let violation = song.validate().first { throw violation }
        progress("Ready")
        return song
    }

    struct Choices: Sendable {
        struct Option: Sendable {
            let song: PreparedSong
            let recommendation: RecommendKeysUseCase.Recommendation
        }
        let options: [Option]
        let excerpt: ClosedRange<TimeInterval>?
        let vocalRange: VocalRange
        /// Separated stems before transposition (the Ready screen plays them in the original key).
        let stems: SeparatedStems
        /// When the guide was built from the lyrics: where each word is sung, `[line][word]` in the
        /// order of the lines passed in. Empty otherwise.
        var guideWords: [[LyricGuideNotesUseCase.Word]] = []
        /// How far the lyric lines were moved to where they are sung (`LyricGuideNotesUseCase.Result.lineShift`).
        var lyricLineShift: TimeInterval = 0
        /// The song just before the trimmed part, separated but not transposed; rendered into each
        /// key as `PreparedSong.leadIn`. Nil when the part starts at the song's start.
        var leadIn: LeadInStems?
    }

    /// Up to the pre-roll of the song before the trimmed part, so the pre-roll plays the beat
    /// instead of silence (user request 2026-11-21).
    struct LeadInStems: Sendable {
        let stems: SeparatedStems
        let duration: TimeInterval
    }

    /// Shorter than this before the part, the pre-roll stays silent (a click at the start is worse).
    static let minimumLeadIn: TimeInterval = 0.5

    /// Separate and analyse once; render only the best fully fitting keys. With `lyricLines` (on
    /// the trimmed timeline), the guide has one note per sung word instead of the raw pitch notes.
    func executeChoices(audioURL: URL, trimRange: ClosedRange<TimeInterval>, vocalRange: VocalRange,
                        lyricLines: [LyricGuideNotesUseCase.Line] = [],
                        recommendationLimit: Int? = nil,
                        progress: @escaping @Sendable (String) -> Void = { _ in }) async throws -> Choices {
        let (stems, extracted) = try await extract(audioURL: audioURL, trimRange: trimRange, progress: progress)
        let duration = trimRange.upperBound - trimRange.lowerBound
        let leadIn = await leadInStems(audioURL: audioURL, trimRange: trimRange, progress: progress)
        try Task.checkCancellation()
        var recognized: [RecognizedWord] = []
        if let wordRecognition, !lyricLines.isEmpty {
            progress("Matching the lyrics")
            recognized = await wordRecognition.recognizeWords(in: stems.vocalGuideURL,
                                                              lyrics: lyricLines.flatMap(\.words).joined(separator: " "))
            try Task.checkCancellation()
        }
        let lyricGuide = LyricGuideNotesUseCase().execute(pitchNotes: extracted, lines: lyricLines, recognized: recognized)
        guard !lyricGuide.notes.isEmpty else {
            // No lyrics: the raw pitch notes, with the tracker's octave errors folded back so the
            // key recommendation does not plan around notes nobody sings.
            return try await makeChoices(stems: stems, notes: LyricGuideNotesUseCase.foldingOctaveErrors(extracted),
                                         duration: duration,
                                         vocalRange: vocalRange, recommendationLimit: recommendationLimit,
                                         leadIn: leadIn, progress: progress)
        }
        var choices = try await makeChoices(stems: stems, notes: lyricGuide.notes, duration: duration,
                                            vocalRange: vocalRange, simplifies: false,
                                            recommendationLimit: recommendationLimit, leadIn: leadIn, progress: progress)
        choices.guideWords = lyricGuide.words
        choices.lyricLineShift = lyricGuide.lineShift
        return choices
    }

    /// Also used by the demo, whose original guide is already known. `simplifies` merges and
    /// bridges pitch fragments; a guide built from the lyrics is already one note per word.
    func makeChoices(stems: SeparatedStems, notes: [TargetMIDINote], duration: TimeInterval,
                     vocalRange: VocalRange, simplifies: Bool = true, recommendationLimit: Int? = nil,
                     leadIn: LeadInStems? = nil,
                     progress: @escaping @Sendable (String) -> Void = { _ in }) async throws -> Choices {
        let slicer = SliceSegmentsUseCase(configuration: configuration)
        // Sanitise timestamps without simplifying away extremes or changing note durations.
        let original = try slicer.execute(notes: notes, duration: duration).flatMap(\.targetNotes)
        guard !original.isEmpty else {
            throw ContractViolation(contract: "Preparation", message: "No guide notes detected.")
        }
        let recommender = RecommendKeysUseCase(configuration: configuration)
        let ranked = try recommender.execute(notes: original, vocalRange: vocalRange)
        let recommendations = Array(ranked.prefix(max(0, recommendationLimit ?? ranked.count)))
        let excerpt = recommender.highestPhrase(notes: original, duration: duration)
        let guide = simplifies ? SimplifyGuideUseCase(configuration: configuration).execute(original) : original
        let segments = try slicer.execute(notes: guide, duration: duration)
        var options: [Choices.Option] = []
        for (index, recommendation) in recommendations.enumerated() {
            try Task.checkCancellation()
            progress("Preparing key \(index + 1) of \(recommendations.count)")
            let shift = recommendation.plan.semitoneShift
            let mix = try await transposition.renderTransposed(stems.mixURL, semitones: shift)
            try Task.checkCancellation()
            let instrumental = try await transposition.renderTransposed(stems.instrumentalURL, semitones: shift)
            try Task.checkCancellation()
            var song = PreparedSong(earphoneMixURL: mix, instrumentalURL: instrumental, segments: segments,
                                    transposition: recommendation.plan, duration: duration, separationMethod: stems.method)
            song.leadIn = await Self.renderLeadIn(leadIn, semitones: shift, transposition: transposition)
            try Task.checkCancellation()
            if let violation = song.validate().first { throw violation }
            options.append(Choices.Option(song: song, recommendation: recommendation))
        }
        var choices = Choices(options: options, excerpt: excerpt, vocalRange: vocalRange, stems: stems)
        choices.leadIn = leadIn
        return choices
    }

    /// The song before the trimmed part, separated like the part itself; nil when there is too
    /// little of it or it fails (the pre-roll is then silent, as before).
    private func leadInStems(audioURL: URL, trimRange: ClosedRange<TimeInterval>,
                             progress: @escaping @Sendable (String) -> Void) async -> LeadInStems? {
        let length = min(configuration.preRoll, trimRange.lowerBound)
        guard length >= Self.minimumLeadIn else { return nil }
        progress("Preparing the lead-in")
        let range = (trimRange.lowerBound - length)...trimRange.lowerBound
        guard let stems = try? await separation.separateStems(from: audioURL, trimRange: range) else { return nil }
        return LeadInStems(stems: stems, duration: length)
    }

    /// `leadIn` in the key `semitones` away, like the song's own tracks; nil when it fails.
    static func renderLeadIn(_ leadIn: LeadInStems?, semitones: Int,
                             transposition: any AudioTranspositionRepository) async -> PreparedSong.LeadIn? {
        guard let leadIn,
              let mix = try? await transposition.renderTransposed(leadIn.stems.mixURL, semitones: semitones),
              let instrumental = try? await transposition.renderTransposed(leadIn.stems.instrumentalURL, semitones: semitones)
        else { return nil }
        return PreparedSong.LeadIn(mixURL: mix, instrumentalURL: instrumental, duration: leadIn.duration)
    }

    private func extract(audioURL: URL, trimRange: ClosedRange<TimeInterval>,
                         progress: @escaping @Sendable (String) -> Void) async throws -> (SeparatedStems, [TargetMIDINote]) {
        guard trimRange.lowerBound.isFinite, trimRange.upperBound.isFinite,
              trimRange.lowerBound >= 0, trimRange.upperBound > trimRange.lowerBound else {
            throw ContractViolation(contract: "Preparation", message: "Invalid trim range.")
        }
        try Task.checkCancellation()
        progress("Separating vocals and backing music")
        let stems = try await separation.separateStems(from: audioURL, trimRange: trimRange)
        progress("Extracting the vocal guide")
        let extracted: [TargetMIDINote]
        do {
            let primary = try await analysis.extractVocalGuideNotes(from: stems.vocalGuideURL)
            guard !primary.isEmpty else {
                throw ContractViolation(contract: "Preparation", message: "No guide notes detected.")
            }
            extracted = primary
        } catch {
            try Task.checkCancellation()
            guard let fallbackAnalysis else { throw error }
            progress("Using fallback pitch analysis")
            extracted = try await fallbackAnalysis.extractVocalGuideNotes(from: stems.vocalGuideURL)
        }
        return (stems, extracted)
    }

}
