//
//  ImportSongViewModel.swift
//  finpro
//
//  Import → trim → prepare (PRD §5.2–5.4): the user picks a song they own, chooses 15–60 s
//  while seeing (and hearing) the synced lyrics of that part, and PrepareSongUseCase separates
//  it, extracts the guide, slices segments and renders the recommended keys to choose from.
//

import Foundation
import Observation

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

    /// PRD §5.2: the trimmed selection is 15–60 s.
    static let minimumLength: TimeInterval = 15
    static let maximumLength: TimeInterval = 60
    private static let defaultLength: TimeInterval = 30

    /// How often the karaoke highlight follows the selection preview (30 fps).
    private static let playbackRefresh: Duration = .milliseconds(33)
    /// The suggested chorus starts this much before its first line (breath, pickup notes)
    /// and ends this much after its last sung word.
    private static let chorusLeadIn: TimeInterval = 1
    private static let chorusTail: TimeInterval = 1

    private(set) var savedSongID: UUID?
    private(set) var actionError: UserFacingError?
    private(set) var status: Status = .idle
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
    /// Key choices kept until the user continues from the "audio is ready" screen.
    @ObservationIgnored private var preparedChoices: PrepareSongUseCase.Choices?
    /// Lyrics of the part being prepared, on the prepared song's timeline (0 = start of the part).
    @ObservationIgnored private var preparedLyrics: [LyricLine] = []
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var lyricsLookup: Task<Void, Never>?
    @ObservationIgnored private var playback: Task<Void, Never>?

    init(inspector: any AudioFileInspecting, lyrics: any LyricsProviding, previewer: any AudioPreviewing,
         prepare: PrepareSongUseCase,
         vocalRange: @escaping () -> VocalRange?,
         library: SongLibrary? = nil, initialSong: SavedSong? = nil,
         onSavedToList: @escaping () -> Void = {},
         onSelectionSaved: @escaping (UUID) -> Void = { _ in },
         onPrepared: @escaping (PrepareSongUseCase.Choices, [LyricLine], String?) -> Void) {
        self.inspector = inspector
        self.lyricsProvider = lyrics
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
    var waveformInterval: ClosedRange<TimeInterval> {
        guard let audio = selectionAudio else { return 0...1 }
        let span = min(audio.duration, max(Self.maximumLength, selectionLength * 2.5))
        let start = min(max(0, selectionStart + selectionLength / 2 - span / 2), max(0, audio.duration - span))
        return start...(start + span)
    }
    var isPreparing: Bool {
        if case .preparing = status { return true }
        return status == .prepared
    }

    var maximumStart: TimeInterval {
        max(0, (audio?.duration ?? 0) - Self.minimumLength)
    }

    var maximumLengthForStart: TimeInterval {
        min(Self.maximumLength, (audio?.duration ?? 0) - selectionStart)
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
        generation = UUID()
        let token = generation
        status = .loading
        importTask = Task {
            do {
                let audio = try await inspector.importFile(at: url)
                guard !Task.isCancelled, generation == token else { return }
                savedSongID = nil
                open(audio)
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
        lyricsTitle = audio.title
        lyricsArtist = audio.artist ?? ""
        userMovedSelection = saved != nil
        actionError = nil
        if let cached = saved?.lyrics { lyrics = .found(cached) } else { searchLyrics() }
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
            preparingDisplayName = song.title
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
        preparedLyrics = lyricsOnPreparedTimeline(trim)
        status = .preparing(step: "Starting…")
        let token = generation
        preparation = Task { [prepare] in
            do {
                let choices = try await prepare.executeChoices(audioURL: audio.url, trimRange: trim, vocalRange: range, recommendationLimit: 1) { step in
                    Task { @MainActor in
                        if self.generation == token, case .preparing = self.status { self.status = .preparing(step: step) }
                    }
                }
                try Task.checkCancellation()
                guard generation == token else { return }
                preparedChoices = choices
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
    var preparationProgress: PreparationProgress? {
        switch status {
        case .prepared:
            return PreparationProgress(fraction: 1, vocals: .done, instrumental: .done)
        case .preparing(let step):
            let fraction: Double
            let separating: Bool
            switch step {
            case _ where step.hasPrefix("Starting"):
                (fraction, separating) = (0.05, true)
            case _ where step.hasPrefix("Separating"):
                (fraction, separating) = (0.2, true)
            case _ where step.hasPrefix("Extracting"), _ where step.hasPrefix("Using fallback"):
                (fraction, separating) = (0.5, false)
            case _ where step.hasPrefix("Building"):
                (fraction, separating) = (0.65, false)
            case _ where step.hasPrefix("Preparing key"):
                (fraction, separating) = (0.75, false)
            case _ where step.hasPrefix("Rendering"):
                (fraction, separating) = (0.9, false)
            case _ where step.hasPrefix("Ready"):
                (fraction, separating) = (0.99, false)
            default:
                (fraction, separating) = (0.05, true)
            }
            let stem: PreparationProgress.StemState = separating ? .processing : .done
            return PreparationProgress(fraction: fraction, vocals: stem, instrumental: stem)
        default:
            return nil
        }
    }

    func reset() {
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

    /// The lines sung in `trim`, shifted so the part starts at 0 like the prepared song.
    private func lyricsOnPreparedTimeline(_ trim: ClosedRange<TimeInterval>) -> [LyricLine] {
        guard case .found(let song) = lyrics else { return [] }
        let offset = trim.lowerBound
        let length = trim.upperBound - trim.lowerBound
        return song.lines
            .filter { ($0.words.last?.end ?? $0.end) > trim.lowerBound && $0.start < trim.upperBound }
            .map { line in
                LyricLine(id: line.id, text: line.text,
                          start: line.start - offset, end: min(length, line.end - offset),
                          words: line.words.map { LyricWord(text: $0.text, start: $0.start - offset, end: $0.end - offset) })
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
                lyrics = found.map(LyricsState.found) ?? .notFound
                if !userMovedSelection { useChorusSuggestion() }
            } catch is CancellationError {
            } catch {
                lyrics = .failed(.lyricsUnavailable)
            }
        }
    }

    /// The chorus' first occurrence as a 15–60 s selection, if the lyrics have a repeated block.
    var chorusSuggestion: (start: TimeInterval, length: TimeInterval)? {
        guard let audio, case .found(let song) = lyrics, let chorus = song.chorus else { return nil }
        let first = song.lines[chorus.lowerBound], last = song.lines[chorus.upperBound - 1]
        let start = max(0, first.start - Self.chorusLeadIn)
        let end = min(audio.duration, (last.words.last?.end ?? last.end) + Self.chorusTail)
        let length = min(Self.maximumLength, max(Self.minimumLength, end - start))
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
        restartingPreview?.cancel()
        stopSelectionPreview()
    }

    func endSelectionEditing() {
        editingSelection = false
        startSelectionPreview()
    }

    func suspend() {
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
        let length = min(max(Self.minimumLength, selectionLength), min(Self.maximumLength, audio.duration - start))
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
