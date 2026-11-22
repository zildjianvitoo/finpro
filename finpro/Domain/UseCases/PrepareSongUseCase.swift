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
        /// How many seconds earlier than the requested trim the part starts: the chosen start fell
        /// inside a sung phrase, so it was moved back to where that phrase begins (`phraseStartBackoff`).
        /// Times on the requested trim's timeline are this much later on the prepared song's.
        var clipStartShift: TimeInterval = 0
    }

    /// Up to the pre-roll of the song before the trimmed part, so the pre-roll plays the beat
    /// instead of silence (user request 2026-11-21).
    struct LeadInStems: Sendable {
        let stems: SeparatedStems
        let duration: TimeInterval
    }

    /// Shorter than this before the part, the pre-roll stays silent (a click at the start is worse).
    static let minimumLeadIn: TimeInterval = 0.5

    // Moving a start that cuts into a sung phrase (device feedback 2026-11-21: synced lyrics are
    // often early or late, so a part picked at a line could start mid-phrase and the lead-in
    // played the line's first words before the part sang them again).
    /// A voiced note ending this close to the start counts as sung across it.
    static let phraseEdgeTolerance: TimeInterval = 0.15
    /// Notes closer than this belong to one phrase (a breath between words is shorter).
    static let phraseGap: TimeInterval = 0.3
    /// The start moves back at most this far; a longer phrase is left as chosen.
    static let maximumPhraseBackoff: TimeInterval = LyricGuideNotesUseCase.lineShiftRange
    /// Moves shorter than this are not worth separating again.
    static let minimumPhraseBackoff: TimeInterval = 0.1
    /// Length of the audio preview played on Find Your Key, starting from the beginning of the
    /// user's chosen section so the preview matches what they just selected.
    static let keyPreviewDuration: TimeInterval = 15

    /// Separate and analyse once; render only the best fully fitting keys. With `lyricLines` (on
    /// the trimmed timeline), the guide has one note per sung word instead of the raw pitch notes.
    func executeChoices(audioURL: URL, trimRange: ClosedRange<TimeInterval>, vocalRange: VocalRange,
                        lyricLines: [LyricGuideNotesUseCase.Line] = [],
                        recommendationLimit: Int? = nil,
                        progress: @escaping @Sendable (String) -> Void = { _ in }) async throws -> Choices {
        guard trimRange.lowerBound.isFinite, trimRange.upperBound.isFinite,
              trimRange.lowerBound >= 0, trimRange.upperBound > trimRange.lowerBound else {
            throw ContractViolation(contract: "Preparation", message: "Invalid trim range.")
        }
        try Task.checkCancellation()

        progress("Separating vocals and backing music")
        var trimRange = trimRange
        var separated = try await separate(audioURL: audioURL, trimRange: trimRange, progress: progress)
        try Task.checkCancellation()
        // A start inside a sung phrase: start where the phrase starts instead (the chunks are
        // cached, so separating again mostly reassembles them).
        let clipStartShift = await phraseStartBackoff(separated.leadIn)
        if clipStartShift > 0 {
            trimRange = (trimRange.lowerBound - clipStartShift)...trimRange.upperBound
            separated = try await separate(audioURL: audioURL, trimRange: trimRange, progress: progress)
            try Task.checkCancellation()
        }
        let (stems, leadIn) = separated
        let duration = trimRange.upperBound - trimRange.lowerBound
        let lyricLines = clipStartShift > 0 ? lyricLines.map { line in
            LyricGuideNotesUseCase.Line(start: line.start + clipStartShift, end: line.end + clipStartShift,
                                        wordWeights: line.wordWeights, words: line.words)
        } : lyricLines

        // Pitch extraction (CREPE) and word recognition (SpeechTranscriber) both read only the
        // separated vocal stem, so they run in parallel.
        progress("Extracting the vocal guide")
        async let extractedTask = analyzeVocalGuide(from: stems.vocalGuideURL, progress: progress)
        async let recognizedTask: [RecognizedWord] = {
            guard let wordRecognition, !lyricLines.isEmpty else { return [] }
            return await wordRecognition.recognizeWords(in: stems.vocalGuideURL,
                                                        lyrics: lyricLines.flatMap(\.words).joined(separator: " "))
        }()
        let extracted = try await extractedTask
        let recognized = await recognizedTask
        try Task.checkCancellation()

        let lyricGuide = LyricGuideNotesUseCase().execute(pitchNotes: extracted, lines: lyricLines, recognized: recognized)
        guard !lyricGuide.notes.isEmpty else {
            // No lyrics: the raw pitch notes, with the tracker's octave errors folded back so the
            // key recommendation does not plan around notes nobody sings.
            var choices = try await makeChoices(stems: stems, notes: LyricGuideNotesUseCase.foldingOctaveErrors(extracted),
                                                duration: duration,
                                                vocalRange: vocalRange, recommendationLimit: recommendationLimit,
                                                leadIn: leadIn, progress: progress)
            choices.clipStartShift = clipStartShift
            return choices
        }
        var choices = try await makeChoices(stems: stems, notes: lyricGuide.notes, duration: duration,
                                            vocalRange: vocalRange, simplifies: false,
                                            recommendationLimit: recommendationLimit, leadIn: leadIn, progress: progress)
        choices.guideWords = lyricGuide.words
        choices.lyricLineShift = lyricGuide.lineShift
        choices.clipStartShift = clipStartShift
        return choices
    }

    /// The trimmed part and the song before it (up to the pre-roll), separated.
    private func separate(audioURL: URL, trimRange: ClosedRange<TimeInterval>,
                          progress: @escaping @Sendable (String) -> Void) async throws -> (stems: SeparatedStems, leadIn: LeadInStems?) {
        let leadLength = min(configuration.preRoll, trimRange.lowerBound)
        let wantsLeadIn = leadLength >= Self.minimumLeadIn
        if let combined = separation as? any LeadInStemSeparation {
            let result = try await combined.separateStems(from: audioURL, trimRange: trimRange,
                                                          leadInDuration: wantsLeadIn ? leadLength : 0)
            return (result.stems, result.leadIn.map { LeadInStems(stems: $0, duration: leadLength) })
        }
        let stems = try await separation.separateStems(from: audioURL, trimRange: trimRange)
        let leadIn = wantsLeadIn ? await leadInStems(audioURL: audioURL, trimRange: trimRange, progress: progress) : nil
        return (stems, leadIn)
    }

    /// How far before the part the phrase sung across its start begins (seconds), from the pitch
    /// notes of the lead-in's vocal stem; 0 when nothing is sung across the start, no quiet gap is
    /// found within `maximumPhraseBackoff`, or the lead-in can't be analysed.
    private func phraseStartBackoff(_ leadIn: LeadInStems?) async -> TimeInterval {
        guard let leadIn,
              let notes = try? await analysis.extractVocalGuideNotes(from: leadIn.stems.vocalGuideURL) else { return 0 }
        return Self.phraseStartBackoff(notes: notes, leadInDuration: leadIn.duration)
    }

    /// `notes` on the lead-in's timeline (0 = its start, `leadInDuration` = the part's start).
    static func phraseStartBackoff(notes: [TargetMIDINote], leadInDuration: TimeInterval) -> TimeInterval {
        let sorted = notes.filter { $0.duration > 0 && $0.startTime < leadInDuration }.sorted { $0.startTime < $1.startTime }
        guard let last = sorted.last, last.endTime >= leadInDuration - phraseEdgeTolerance else { return 0 }
        var phraseStart = last.startTime
        for note in sorted.dropLast().reversed() {
            guard phraseStart - note.endTime < phraseGap else { break }
            phraseStart = min(phraseStart, note.startTime)
        }
        // The consonant before the first steady pitch belongs to the phrase too.
        let start = phraseStart - LyricGuideNotesUseCase.attackLead
        // No quiet gap inside the lead-in: the phrase may start even earlier, so leave the start alone.
        guard start > 0 else { return 0 }
        let backoff = leadInDuration - start
        return backoff >= minimumPhraseBackoff && backoff <= maximumPhraseBackoff ? backoff : 0
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
        let previewEnd = min(duration, Self.keyPreviewDuration)
        let excerpt: ClosedRange<TimeInterval>? = previewEnd > 0 ? 0...previewEnd : nil
        let guide = simplifies ? SimplifyGuideUseCase(configuration: configuration).execute(original) : original
        let segments = try slicer.execute(notes: guide, duration: duration)
        var options: [Choices.Option] = []
        for (index, recommendation) in recommendations.enumerated() {
            try Task.checkCancellation()
            progress("Preparing key \(index + 1) of \(recommendations.count)")
            let shift = recommendation.plan.semitoneShift
            async let mixTask = transposition.renderTransposed(stems.mixURL, semitones: shift)
            async let instrumentalTask = transposition.renderTransposed(stems.instrumentalURL, semitones: shift)
            async let leadInTask = Self.renderLeadIn(leadIn, semitones: shift, transposition: transposition)
            let mix = try await mixTask
            let instrumental = try await instrumentalTask
            let renderedLeadIn = await leadInTask
            try Task.checkCancellation()
            var song = PreparedSong(earphoneMixURL: mix, instrumentalURL: instrumental, segments: segments,
                                    transposition: recommendation.plan, duration: duration, separationMethod: stems.method)
            song.leadIn = renderedLeadIn
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
        guard let leadIn else { return nil }
        async let mixTask = try? transposition.renderTransposed(leadIn.stems.mixURL, semitones: semitones)
        async let instrumentalTask = try? transposition.renderTransposed(leadIn.stems.instrumentalURL, semitones: semitones)
        guard let mix = await mixTask, let instrumental = await instrumentalTask else { return nil }
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
        let extracted = try await analyzeVocalGuide(from: stems.vocalGuideURL, progress: progress)
        return (stems, extracted)
    }

    private func analyzeVocalGuide(from vocalGuideURL: URL,
                                   progress: @escaping @Sendable (String) -> Void) async throws -> [TargetMIDINote] {
        do {
            let primary = try await analysis.extractVocalGuideNotes(from: vocalGuideURL)
            guard !primary.isEmpty else {
                throw ContractViolation(contract: "Preparation", message: "No guide notes detected.")
            }
            return primary
        } catch {
            try Task.checkCancellation()
            guard let fallbackAnalysis else { throw error }
            progress("Using fallback pitch analysis")
            return try await fallbackAnalysis.extractVocalGuideNotes(from: vocalGuideURL)
        }
    }

}
