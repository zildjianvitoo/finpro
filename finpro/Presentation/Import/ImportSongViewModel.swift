//
//  ImportSongViewModel.swift
//  finpro
//
//  Import → trim → prepare (PRD §5.2–5.4): the user picks a song they own, chooses a part (15 s up
//  to the whole song)
//  while seeing (and hearing) the synced lyrics of that part, and PrepareSongUseCase separates
//  it, extracts the guide, slices segments and renders the recommended keys to choose from.
//

import Foundation
import Observation
import os

@Observable
final class ImportSongViewModel {
    enum Status: Equatable {
        case idle
        case loading
        case trimming(ImportedAudio)
        case preparing(step: String)
        /// Separation and key rendering finished; waits for the user to continue.
        case prepared
        case failed(UserFacingError)
    }

    /// What the preparing screen shows: overall progress and the state of each stem.
    struct PreparationProgress: Equatable {
        enum StemState: Equatable {
            case waiting, processing, done
        }

        let fraction: Double
        let vocals: StemState
        let instrumental: StemState
        var isComplete: Bool { fraction >= 1 }
    }

    enum LyricsState: Equatable {
        case idle
        case loading
        case found(SongLyrics)
        case notFound
        case failed(UserFacingError)
    }

    /// The trimmed selection is at least 15 s; it may be as long as the whole song.
    static let minimumLength: TimeInterval = 15
    private static let defaultLength: TimeInterval = 30
    /// Waveform zoom: at least this much song is in view (less for shorter songs, see below).
    private static let waveformMinimumVisible: TimeInterval = 90
    /// …and the selection fills at most this share of the width, so both edges stay reachable.
    private static let waveformSelectionShare = 0.7

    /// How often the karaoke highlight follows the selection preview (30 fps).
    private static let playbackRefresh: Duration = .milliseconds(33)
    /// The suggested chorus starts this much before its first line (breath, pickup notes)
    /// and ends this much after its last sung word.
    private static let chorusLeadIn: TimeInterval = 1
    private static let chorusTail: TimeInterval = 1
    /// The lead-in never reaches into the line before the chorus: it stops this long after that
    /// line ends (half the gap that separates phrases, see `AppConfiguration.segmentGap`), so the
    /// clip does not open on a fragment of it (a stray "wanna see" became a 1 s clip). The line's
    /// timed end is used, not its estimated last word, which often ends before it is really sung.
    private static let chorusLeadInClearance = AppConfiguration.default.segmentGap / 2

    private(set) var savedSongID: UUID?
    private(set) var actionError: UserFacingError?
    private(set) var status: Status = .idle {
        didSet {
            if case .preparing(let step) = status, stepStarted?.step != step { stepStarted = (step, .now) }
            if case .preparing = status {} else { stepStarted = nil }
        }
    }
    /// When the current preparation step began, so the progress keeps moving within a long step.
    @ObservationIgnored private var stepStarted: (step: String, at: ContinuousClock.Instant)?
    var selectionStart: TimeInterval = 0 { didSet { selectionChanged() } }
    var selectionLength: TimeInterval = defaultLength { didSet { selectionChanged() } }
    private(set) var lyrics: LyricsState = .idle
    /// Manual lyrics search, prefilled from the file's metadata or name.
    var lyricsTitle = ""
    var lyricsArtist = ""
    /// Position in the song while the selection preview plays, nil otherwise.
    private(set) var playbackTime: TimeInterval?
    /// True once the user moved a slider; the chorus suggestion then no longer replaces their pick.
    @ObservationIgnored private var userMovedSelection = false
    @ObservationIgnored private var applyingSuggestion = false

    @ObservationIgnored private let inspector: any AudioFileInspecting
    @ObservationIgnored private let lyricsProvider: any LyricsProviding
    @ObservationIgnored private let recognizer: (any SongRecognizing)?
    @ObservationIgnored private var recognition: Task<Void, Never>?
    /// Shazam's answer for the open song: nil until it answers, `.some(nil)` when it had no match.
    @ObservationIgnored private var recognized: RecognizedSong??
    /// Shazam is still naming the open song (the lyrics area says so while it waits).
    private(set) var isIdentifyingSong = false
    @ObservationIgnored private var recognitionToken = UUID()
    /// The file's name found no lyrics while Shazam was still working: the lyrics area keeps
    /// loading until Shazam answers, instead of showing the manual search form in between.
    @ObservationIgnored private var lyricsAwaitRecognition = false
    @ObservationIgnored private let previewer: any AudioPreviewing
    @ObservationIgnored private let prepare: PrepareSongUseCase
    @ObservationIgnored private let vocalRange: () -> VocalRange?
    /// Called with the key choices (each holds a prepared song, and `stems` the untransposed
    /// stems) and the lyrics of the chosen part on the prepared song's timeline.
    @ObservationIgnored private let onPrepared: (PrepareSongUseCase.Choices, [LyricLine], String?) -> Void
    @ObservationIgnored private var preparation: Task<Void, Never>?
    @ObservationIgnored private var importTask: Task<Void, Never>?
    @ObservationIgnored private let library: SongLibrary?
    @ObservationIgnored private let initialSong: SavedSong?
    @ObservationIgnored private let onSelectionSaved: (UUID) -> Void
    @ObservationIgnored private let onSavedToList: () -> Void
    @ObservationIgnored private var editingSelection = false
    @ObservationIgnored private var restartingPreview: Task<Void, Never>?
    /// The song being prepared, to return to its trimmer when going back.
    @ObservationIgnored private var preparingDisplayName: String?
    @ObservationIgnored private var preparingAudio: ImportedAudio?
    @ObservationIgnored private var preparingLength: TimeInterval = 30
    /// Key choices kept until the user continues from the "audio is ready" screen.
    @ObservationIgnored private var preparedChoices: PrepareSongUseCase.Choices?
    /// Lyrics of the part being prepared, on the prepared song's timeline (0 = start of the part).
    @ObservationIgnored private var preparedLyrics: [LyricLine] = []
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var lyricsLookup: Task<Void, Never>?
    @ObservationIgnored private var playback: Task<Void, Never>?

    init(inspector: any AudioFileInspecting, lyrics: any LyricsProviding,
         recognizer: (any SongRecognizing)? = nil, previewer: any AudioPreviewing,
         prepare: PrepareSongUseCase,
         vocalRange: @escaping () -> VocalRange?,
         library: SongLibrary? = nil, initialSong: SavedSong? = nil,
         onSavedToList: @escaping () -> Void = {},
         onSelectionSaved: @escaping (UUID) -> Void = { _ in },
         onPrepared: @escaping (PrepareSongUseCase.Choices, [LyricLine], String?) -> Void) {
        self.inspector = inspector
        self.lyricsProvider = lyrics
        self.recognizer = recognizer
        self.previewer = previewer
        self.prepare = prepare
        self.vocalRange = vocalRange
        self.onPrepared = onPrepared
        self.library = library
        self.initialSong = initialSong
        self.onSavedToList = onSavedToList
        self.onSelectionSaved = onSelectionSaved
    }

    var audio: ImportedAudio? {
        if case .trimming(let audio) = status { audio } else { nil }
    }

    var selectionAudio: ImportedAudio? { audio ?? preparingAudio }
    /// Seconds of song across the waveform's width. It zooms out to fit a longer selection, but
    /// only once a drag ends: while the user drags, the scale stays fixed so nothing jumps.
    var waveformVisibleSeconds: TimeInterval {
        if let frozenVisibleSeconds { return frozenVisibleSeconds }
        let duration = selectionAudio?.duration ?? 0
        let base = min(Self.waveformMinimumVisible, max(Self.waveformMinimumVisible * 2 / 3, duration))
        return max(base, selectionLength / Self.waveformSelectionShare)
    }
    @ObservationIgnored private var frozenVisibleSeconds: TimeInterval?

    /// The part of the song in view: the selection sits in the middle (the waveform scrolls under it).
    var waveformInterval: ClosedRange<TimeInterval> {
        guard selectionAudio != nil else { return 0...1 }
        let start = selectionStart + selectionLength / 2 - waveformVisibleSeconds / 2
        return start...(start + waveformVisibleSeconds)
    }
    var isPreparing: Bool {
        if case .preparing = status { return true }
        return status == .prepared
    }

    var maximumStart: TimeInterval {
        max(0, (audio?.duration ?? 0) - Self.minimumLength)
    }

    var maximumLengthForStart: TimeInterval {
        (audio?.duration ?? 0) - selectionStart
    }

    func openInitialSong() {
        guard status == .idle, let initialSong, let library else { return }
        savedSongID = initialSong.id
        open(library.audio(for: initialSong), saved: initialSong)
    }

    func picked(_ result: Result<URL, any Error>) {
        guard case .success(let url) = result else { return }
        importTask?.cancel()
        stopSelectionPreview()
        lyricsLookup?.cancel()
        recognition?.cancel()
        generation = UUID()
        let token = generation
        status = .loading
        importTask = Task {
            do {
                let audio = try await inspector.importFile(at: url)
                guard !Task.isCancelled, generation == token else { return }
                if let library, let existing = library.song(matching: audio) {
                    // The same file again: continue with its saved song (section, lyrics, caches).
                    savedSongID = existing.id
                    open(library.audio(for: existing), saved: existing)
                } else {
                    savedSongID = nil
                    open(audio)
                }
            } catch {
                guard !Task.isCancelled, generation == token else { return }
                status = .failed(Self.userFacing(error))
            }
        }
    }

    private func open(_ audio: ImportedAudio, saved: SavedSong? = nil) {
        guard audio.duration >= Self.minimumLength else {
            status = .failed(.songTooShort(minimumSeconds: Int(Self.minimumLength)))
            return
        }
        status = .loading
        selectionStart = saved?.selectionStart ?? 0
        selectionLength = saved?.selectionLength ?? min(Self.defaultLength, audio.duration)
        status = .trimming(audio)
        clampSelection()
        // A song Shazam already named searches lyrics by that name.
        let named = saved?.isRecognitionDone == true || saved?.isRenamedByUser == true
        lyricsTitle = named ? saved?.title ?? audio.title : audio.title
        lyricsArtist = (named ? saved?.displayArtist : nil) ?? audio.artist ?? ""
        userMovedSelection = saved != nil
        actionError = nil
        recognized = nil
        recognition?.cancel()
        isIdentifyingSong = false
        lyricsAwaitRecognition = false
        let recognizes = recognizer != nil && !named
        // Lyrics are searched right away with the file's name; Shazam runs alongside and, if the
        // file's name finds nothing, its name is tried as well.
        if let cached = saved?.lyrics { lyrics = .found(cached) } else { searchLyrics() }
        if recognizes { recognize(audio) }
        startSelectionPreview()
    }

    /// Keeps a durable copy even when the user goes directly to key selection.
    @discardableResult
    private func persistSelection() -> Bool {
        guard let library, let audio else { return true }
        let cached: SongLyrics?
        if case .found(let song) = lyrics { cached = song } else { cached = nil }
        do {
            let song = try library.save(audio: audio, existingID: savedSongID,
                                        start: selectionStart, length: selectionLength, lyrics: cached)
            savedSongID = song.id
            onSelectionSaved(song.id)
            let named = recognized.flatMap { library.applyRecognition(song.id, song: $0) } ?? song
            preparingDisplayName = named.title
            actionError = nil
            return true
        } catch {
            actionError = .songLibraryFailed
            return false
        }
    }

    func saveToSongList() {
        guard audio != nil, persistSelection() else { return }
        stopSelectionPreview()
        onSavedToList()
    }

    func prepareSelection() {
        guard let audio, let range = vocalRange(), persistSelection() else { return }
        stopSelectionPreview()
        generation = UUID()
        let trim = selectionStart...(selectionStart + selectionLength)
        preparingAudio = audio
        preparingLength = selectionLength
        let lyrics = lyricsOnPreparedTimeline(trim)
        preparedLyrics = lyrics
        // The parser spread each line's words by syllable count, so their lengths are the weights.
        let lyricLines = lyrics.map { line in
            LyricGuideNotesUseCase.Line(start: line.start, end: line.end, wordWeights: line.words.map { $0.end - $0.start })
        }
        status = .preparing(step: "Starting…")
        let token = generation
        preparation = Task { [prepare] in
            do {
                let choices = try await prepare.executeChoices(audioURL: audio.url, trimRange: trim, vocalRange: range,
                                                               lyricLines: lyricLines, recommendationLimit: 1) { step in
                    Task { @MainActor in
                        if self.generation == token, case .preparing = self.status { self.status = .preparing(step: step) }
                    }
                }
                try Task.checkCancellation()
                guard generation == token else { return }
                preparedChoices = choices
                preparedLyrics = Self.lyrics(lyrics, sungAt: choices.guideWords, shift: choices.lyricLineShift)
                Self.logPrepared(choices, lyricLines: lyricLines.count, file: audio.url.lastPathComponent, trim: trim)
                status = .prepared
            } catch is CancellationError {
                guard generation == token else { return }
                status = .trimming(audio)
            } catch {
                guard generation == token else { return }
                status = .failed(Self.userFacing(error))
            }
        }
    }

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "finpro", category: "Preparation")

    /// Which guide the keys were planned on and what came out, to trace a surprising key choice.
    private static func logPrepared(_ choices: PrepareSongUseCase.Choices, lyricLines: Int, file: String,
                                    trim: ClosedRange<TimeInterval>) {
        let range = "\(PitchMath.noteName(midi: Int(choices.vocalRange.lowestMIDI.rounded())))-\(PitchMath.noteName(midi: Int(choices.vocalRange.highestMIDI.rounded())))"
        let keys = choices.options.map {
            "\($0.song.transposition.semitoneShift)(\(PitchMath.noteName(midi: $0.recommendation.lowestMIDI))-\(PitchMath.noteName(midi: $0.recommendation.highestMIDI)), fits \($0.recommendation.fitsRange))"
        }.joined(separator: ", ")
        log.notice("prepared \(file, privacy: .public) \(trim.lowerBound, privacy: .public)-\(trim.upperBound, privacy: .public) s: lyric lines \(lyricLines, privacy: .public), guide \(choices.guideWords.isEmpty ? "raw pitch" : "lyrics", privacy: .public), range \(range, privacy: .public), keys \(keys, privacy: .public)")
    }

    func cancelPreparation() {
        preparation?.cancel()
        preparation = nil
    }

    /// From the "audio is ready" screen: hand the key choices to the next step.
    func continueWithPreparedSong() {
        guard let preparedChoices else { return }
        onPrepared(preparedChoices, preparedLyrics, preparingDisplayName ?? preparingAudio.map(Self.displayName))
    }

    /// "Artist - Title", or just the title when the artist is unknown.
    private static func displayName(of audio: ImportedAudio) -> String {
        [audio.artist, audio.title].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " - ")
    }

    /// Back from the preparing or ready screen to the trimmer of the same song.
    func backToTrimming() {
        cancelPreparation()
        preparedChoices = nil
        if let preparingAudio { status = .trimming(preparingAudio) }
    }

    /// Progress of the preparation, mapped from the steps PrepareSongUseCase reports. Separation
    /// produces both stems at once, so they share a state; later steps (guide, segments, keys)
    /// move the overall progress.
    var preparationProgress: PreparationProgress? { preparationProgress(at: .now) }

    /// Progress at each step's start; within a step it eases toward the next one (never past it),
    /// so the long separation does not sit on one number for a minute.
    private static let progressSteps: [(prefix: String, fraction: Double, separating: Bool)] = [
        ("Starting", 0.05, true), ("Separating", 0.2, true), ("Extracting", 0.5, false), ("Using fallback", 0.5, false),
        ("Building", 0.65, false), ("Preparing key", 0.75, false), ("Rendering", 0.9, false), ("Ready", 0.99, false),
    ]
    /// Seconds to cover about two thirds of the way to the next step (separation is the long one).
    private static let separatingEasing: Double = 15
    private static let stepEasing: Double = 3
    /// Share of the gap to the next step a step may fill on its own.
    private static let stepFillLimit = 0.9

    func preparationProgress(at now: ContinuousClock.Instant) -> PreparationProgress? {
        switch status {
        case .prepared:
            return PreparationProgress(fraction: 1, vocals: .done, instrumental: .done)
        case .preparing(let step):
            let index = Self.progressSteps.firstIndex { step.hasPrefix($0.prefix) }
            let current = index.map { Self.progressSteps[$0] } ?? Self.progressSteps[0]
            let next = index.flatMap { Self.progressSteps.dropFirst($0 + 1).first { $0.fraction > current.fraction } }?.fraction ?? 1
            let elapsed = stepStarted.map { (now - $0.at) / .seconds(1) } ?? 0
            // Separation and analysis take about as long as the part is; the easings are for 30 s.
            let lengthFactor = max(1, preparingLength / Self.defaultLength)
            let easing = (current.separating ? Self.separatingEasing : Self.stepEasing) * lengthFactor
            let fraction = current.fraction + (next - current.fraction) * Self.stepFillLimit * (1 - exp(-max(0, elapsed) / easing))
            let stem: PreparationProgress.StemState = current.separating ? .processing : .done
            return PreparationProgress(fraction: fraction, vocals: stem, instrumental: stem)
        default:
            return nil
        }
    }

    func reset() {
        recognition?.cancel()
        isIdentifyingSong = false
        lyricsAwaitRecognition = false
        cancelPreparation()
        importTask?.cancel()
        importTask = nil
        restartingPreview?.cancel()
        generation = UUID()
        stopSelectionPreview()
        lyricsLookup?.cancel()
        lyrics = .idle
        savedSongID = nil
        actionError = nil
        status = .idle
    }

    // MARK: - Lyrics

    /// The lines and words moved to where the guide found them sung, so the lyrics card and the
    /// pitch guide agree. Lines are left as they were when the guide was not built from the lyrics.
    private static func lyrics(_ lines: [LyricLine], sungAt guideWords: [[LyricGuideNotesUseCase.Word]],
                               shift: TimeInterval) -> [LyricLine] {
        guard guideWords.count == lines.count else { return lines }
        return zip(lines, guideWords).map { line, sung in
            let words = sung.count == line.words.count
                ? zip(line.words, sung).map { LyricWord(text: $0.text, start: $1.start, end: $1.end) }
                : line.words.map { LyricWord(text: $0.text, start: $0.start + shift, end: $0.end + shift) }
            return LyricLine(id: line.id, text: line.text, start: line.start + shift, end: line.end + shift, words: words)
        }
    }

    /// The lines sung in `trim`, shifted so the part starts at 0 like the prepared song.
    private func lyricsOnPreparedTimeline(_ trim: ClosedRange<TimeInterval>) -> [LyricLine] {
        guard case .found(let song) = lyrics else { return [] }
        return song.lines.compactMap { $0.clipped(to: trim) }
    }

    /// Asks Shazam for the song's name. A match becomes the lyrics search terms and, once the song
    /// is in the Song List, its name there. When Shazam can't be reached the file's name stays.
    private func recognize(_ audio: ImportedAudio) {
        guard let recognizer else { return }
        let token = UUID()
        recognitionToken = token
        isIdentifyingSong = true
        // Not tied to `generation`: starting the preparation must not drop the answer. Picking
        // another file, closing the sheet or opening another song cancels this task instead.
        recognition = Task { [recognizer] in
            let outcome: RecognizedSong??
            do { outcome = .some(try await recognizer.recognize(fileAt: audio.url, duration: audio.duration)) }
            catch { outcome = nil }
            guard !Task.isCancelled, recognitionToken == token, selectionAudio?.url == audio.url else { return }
            isIdentifyingSong = false
            let waited = lyricsAwaitRecognition
            lyricsAwaitRecognition = false
            var renamed = false
            if let outcome {
                recognized = outcome
                if let song = outcome, case let terms = (song.title, song.artist ?? ""), terms != (lyricsTitle, lyricsArtist) {
                    lyricsTitle = terms.0
                    lyricsArtist = terms.1
                    renamed = true
                }
            }
            // The file's name found nothing: search again with Shazam's name, or give up now.
            switch lyrics {
            case .notFound, .failed, .idle: if renamed { searchLyrics() }
            case .loading: if waited { if renamed { searchLyrics() } else { lyrics = .notFound } }
            case .found: break
            }
            if let outcome {
                if let savedSongID, let named = library?.applyRecognition(savedSongID, song: outcome) {
                    // The cover is named after the song when it is being prepared already.
                    if preparingDisplayName != nil { preparingDisplayName = named.title }
                }
            }
        }
    }

    /// Looks up synced lyrics for `lyricsTitle` / `lyricsArtist` (also the manual search).
    func searchLyrics() {
        guard let audio else { return }
        let title = lyricsTitle.trimmingCharacters(in: .whitespaces)
        let artist = lyricsArtist.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else {
            lyrics = .notFound
            return
        }
        lyricsLookup?.cancel()
        lyrics = .loading
        lyricsLookup = Task { [lyricsProvider] in
            do {
                let found = try await lyricsProvider.lyrics(title: title, artist: artist.isEmpty ? nil : artist,
                                                            duration: audio.duration)
                try Task.checkCancellation()
                // Shazam named the song while this search ran: try that name before giving up.
                let current = (lyricsTitle.trimmingCharacters(in: .whitespaces), lyricsArtist.trimmingCharacters(in: .whitespaces))
                if found == nil, current != (title, artist), !current.0.isEmpty {
                    searchLyrics()
                    return
                }
                if found == nil, isIdentifyingSong {
                    // Shazam may still name the song; keep loading until it answers (see `recognize`).
                    lyricsAwaitRecognition = true
                    return
                }
                lyrics = found.map(LyricsState.found) ?? .notFound
                if !userMovedSelection { useChorusSuggestion() }

            } catch is CancellationError {
            } catch {
                lyrics = .failed(.lyricsUnavailable)
            }
        }
    }

    /// The chorus' first occurrence as a selection of at least 15 s, if the lyrics have a repeated block.
    var chorusSuggestion: (start: TimeInterval, length: TimeInterval)? {
        guard let audio, case .found(let song) = lyrics, let chorus = song.chorus else { return nil }
        let first = song.lines[chorus.lowerBound], last = song.lines[chorus.upperBound - 1]
        var start = max(0, first.start - Self.chorusLeadIn)
        if chorus.lowerBound > 0 {
            let previous = song.lines[chorus.lowerBound - 1]
            let previousEnd = previous.end + Self.chorusLeadInClearance
            start = max(start, min(previousEnd, first.start))
        }
        let end = min(audio.duration, (last.words.last?.end ?? last.end) + Self.chorusTail)
        let length = max(Self.minimumLength, end - start)
        // A chorus near the end of a song may need to start earlier to fit the minimum length.
        return (min(start, max(0, audio.duration - length)), length)
    }

    /// Whether the selection is still the suggested chorus.
    var isOnChorusSuggestion: Bool {
        guard let suggestion = chorusSuggestion else { return false }
        return abs(selectionStart - suggestion.start) < 0.05 && abs(selectionLength - suggestion.length) < 0.05
    }

    /// Selects the suggested chorus (automatically once lyrics arrive, or from "Back to Chorus").
    func useChorusSuggestion() {
        guard let suggestion = chorusSuggestion else { return }
        let wasPlaying = isPlayingSelection
        applyingSuggestion = true
        selectionStart = suggestion.start
        selectionLength = suggestion.length
        applyingSuggestion = false
        if wasPlaying { startSelectionPreview() }
    }

    /// Whether a lyric line's sung part is (partly) inside the chosen part.
    func isInSelection(_ line: LyricLine) -> Bool {
        (line.words.last?.end ?? line.end) > selectionStart && line.start < selectionStart + selectionLength
    }

    /// The first line of the chosen part, to scroll to.
    var firstSelectedLineID: Int? {
        guard case .found(let song) = lyrics else { return nil }
        return song.lines.first(where: isInSelection)?.id
    }

    /// The line being sung during the selection preview.
    var activeLineID: Int? {
        guard let time = playbackTime, case .found(let song) = lyrics else { return nil }
        return song.lines.last { $0.start <= time && time < $0.end }?.id
    }

    // MARK: - Selection preview

    var isPlayingSelection: Bool { playbackTime != nil }

    /// Plays the chosen part of the original song; the lyrics follow it.
    func toggleSelectionPreview() {
        if isPlayingSelection { stopSelectionPreview() } else { startSelectionPreview() }
    }

    func startSelectionPreview() {
        stopSelectionPreview()
        guard let audio else { return }
        do { try previewer.play(audio.url, from: selectionStart) }
        catch { actionError = .keyPreviewFailed; return }
        actionError = nil
        playbackTime = selectionStart
        playback = Task { [previewer] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.playbackRefresh)
                guard !Task.isCancelled else { return }
                guard let time = previewer.currentTime else { break }
                if time >= selectionStart + selectionLength {
                    do { try previewer.play(audio.url, from: selectionStart) }
                    catch { actionError = .keyPreviewFailed; break }
                    playbackTime = selectionStart
                } else { playbackTime = time }
            }
            if !Task.isCancelled { stopSelectionPreview() }
        }
    }

    func selectLyric(_ line: LyricLine, extending: Bool = false) {
        beginSelectionEditing()
        if extending {
            selectionLength = line.end - selectionStart
        } else {
            selectionStart = min(line.start, maximumStart)
        }
        endSelectionEditing()
    }

    func beginSelectionEditing() {
        guard !editingSelection else { return }
        editingSelection = true
        frozenVisibleSeconds = waveformVisibleSeconds
        restartingPreview?.cancel()
        stopSelectionPreview()
    }

    func endSelectionEditing() {
        editingSelection = false
        frozenVisibleSeconds = nil
        startSelectionPreview()
    }

    func suspend() {
        recognition?.cancel()
        isIdentifyingSong = false
        lyricsAwaitRecognition = false
        stopSelectionPreview()
        restartingPreview?.cancel()
        lyricsLookup?.cancel()
        importTask?.cancel()
        generation = UUID()
        cancelPreparation()
    }

    func stopSelectionPreview() {
        let ownsPlayback = playback != nil || playbackTime != nil
        playback?.cancel()
        playback = nil
        if ownsPlayback { previewer.stop() }
        playbackTime = nil
    }

    private func selectionChanged() {
        clampSelection()
        if !applyingSuggestion, audio != nil { userMovedSelection = true }
        // Moving the selection ends the preview of the old part.
        if isPlayingSelection { stopSelectionPreview() }
    }

    private func clampSelection() {
        guard let audio else { return }
        let start = min(max(0, selectionStart), max(0, audio.duration - Self.minimumLength))
        let length = min(max(Self.minimumLength, selectionLength), audio.duration - start)
        if start != selectionStart { selectionStart = start }
        if length != selectionLength { selectionLength = length }
    }

    private static func userFacing(_ error: any Error) -> UserFacingError {
        if let convertible = error as? any UserFacingConvertible { return convertible.userFacingError }
        switch error {
        case AudioImportError.protectedContent: return .protectedFile
        case AudioImportError.noAudio, AudioImportError.unreadable: return .unreadableFile
        case let violation as ContractViolation where violation.contract == "Preparation" && violation.message.contains("vocal"):
            return .noVocalDetected
        case let violation as ContractViolation where violation.message.contains("guide notes"):
            return .noVocalDetected
        default: return .keyPreparationFailed
        }
    }
}
