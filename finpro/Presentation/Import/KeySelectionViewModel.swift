//
//  KeySelectionViewModel.swift
//  finpro
//

import Foundation
import Observation
import os

@Observable
final class KeySelectionViewModel {
    let choices: PrepareSongUseCase.Choices
    private(set) var selectedShift: Int?
    private(set) var selectedSong: PreparedSong?
    private(set) var isRendering = false
    private(set) var isManualPreviewPlaying = false
    private(set) var selectedIndex: Int?
    private(set) var playingIndex: Int?
    private(set) var loadingIndex: Int?
    private(set) var error: UserFacingError?

    @ObservationIgnored private let previewer: any AudioPreviewing
    @ObservationIgnored private let onChoose: (PreparedSong) -> Void
    @ObservationIgnored private let renderer: RenderSongKeyUseCase?
    @ObservationIgnored private var rendering: Task<Void, Never>?
    @ObservationIgnored private var rendered: [Int: PreparedSong] = [:]
    @ObservationIgnored private var request = UUID()
    @ObservationIgnored private var playback: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()

    /// A preview that fails is tried once more after this pause: right after the song is prepared
    /// (or the import sheet closes and stops the shared player) the first attempt can fail once.
    private static let previewRetryDelay: Duration = .milliseconds(300)
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "finpro", category: "KeyPreview")

    init(choices: PrepareSongUseCase.Choices, previewer: any AudioPreviewing,
         renderer: RenderSongKeyUseCase? = nil, automaticallySelectRecommended: Bool = false,
         onChoose: @escaping (PreparedSong) -> Void) {
        self.choices = choices
        self.previewer = previewer
        self.onChoose = onChoose
        self.renderer = renderer
        for option in choices.options { rendered[option.song.transposition.semitoneShift] = option.song }
        if automaticallySelectRecommended, let option = choices.options.first {
            selectedIndex = 0
            selectedShift = option.song.transposition.semitoneShift
            selectedSong = option.song
        }
    }

    var recommendedShift: Int? { choices.options.first?.song.transposition.semitoneShift }
    var selectedNotes: (low: Int, high: Int)? {
        guard let selectedSong else { return nil }
        let pitches = selectedSong.segments.flatMap(\.targetNotes).map { selectedSong.transposition.transposed($0) }
        guard let low = pitches.min(), let high = pitches.max() else { return nil }
        return (low, high)
    }
    var fitsRange: Bool {
        guard let selectedNotes else { return false }
        return Float(selectedNotes.low) >= choices.vocalRange.lowestMIDI && Float(selectedNotes.high) <= choices.vocalRange.highestMIDI
    }
    func chooseShift(_ shift: Int) {
        guard TranspositionPlan.semitoneRange.contains(shift), let base = choices.options.first?.song else { return }
        stopPreview()
        rendering?.cancel()
        request = UUID()
        let token = request
        selectedShift = shift
        selectedSong = nil
        selectedIndex = choices.options.firstIndex { $0.song.transposition.semitoneShift == shift }
        error = nil
        if let cached = rendered[shift] { selectedSong = cached; isRendering = false; previewSelected(); return }
        guard let renderer else { isRendering = false; error = .keyPreparationFailed; return }
        isRendering = true
        rendering = Task {
            do {
                // Debounce a drag so intermediate slider positions do not render files.
                try await Task.sleep(for: .milliseconds(180))
                let song = try await renderer.execute(base: base, stems: choices.stems, semitones: shift)
                guard !Task.isCancelled, request == token else { return }
                rendered[shift] = song
                selectedSong = song
                isRendering = false
                previewSelected()
            } catch is CancellationError {
            } catch {
                guard request == token else { return }
                isRendering = false
                self.error = .keyPreparationFailed
            }
        }
    }
    /// Screen entry is idempotent: never toggle an already playing preview off.
    func autoplaySelected() {
        guard !isManualPreviewPlaying, !isRendering else { return }
        if selectedSong != nil { previewSelected() }
        else if let recommendedShift { chooseShift(recommendedShift) }
    }

    func previewSelected() {
        guard let song = selectedSong else { return }
        if isManualPreviewPlaying { stopPreview(); return }
        stopPreview()
        guard let excerpt = choices.excerpt else { return }
        let token = generation
        isManualPreviewPlaying = true
        error = nil
        playback = Task { [self] in
            let onFinish: @Sendable () -> Void = { [weak self] in
                Task { @MainActor in
                    guard let self, self.generation == token else { return }
                    self.isManualPreviewPlaying = false
                    self.playback = nil
                }
            }
            do {
                do {
                    try await previewer.play(song.earphoneMixURL, excerpt: excerpt, onCompletion: onFinish)
                } catch {
                    // Our own stop() changes `generation`; anything else is worth one more try.
                    guard !Task.isCancelled, generation == token else { return }
                    Self.log.notice("key preview failed, retrying: \(String(describing: error), privacy: .public)")
                    try await Task.sleep(for: Self.previewRetryDelay)
                    guard generation == token else { return }
                    try await previewer.play(song.earphoneMixURL, excerpt: excerpt, onCompletion: onFinish)
                }
            } catch {
                guard !Task.isCancelled, generation == token else { return }
                Self.log.error("key preview failed: \(String(describing: error), privacy: .public), excerpt \(excerpt.lowerBound, privacy: .public)-\(excerpt.upperBound, privacy: .public), file \(song.earphoneMixURL.lastPathComponent, privacy: .public)")
                isManualPreviewPlaying = false
                self.error = .keyPreviewFailed
            }
        }
    }

    func listen(_ index: Int) {
        let wasActive = playingIndex == index || loadingIndex == index
        stop()
        guard !wasActive, choices.options.indices.contains(index), let excerpt = choices.excerpt else { return }
        let token = generation
        loadingIndex = index
        error = nil
        playback = Task { [self] in
            do {
                try await previewer.play(choices.options[index].song.earphoneMixURL, excerpt: excerpt) { [weak self] in
                    Task { @MainActor in
                        guard let self, self.generation == token else { return }
                        self.playingIndex = nil
                        self.loadingIndex = nil
                    }
                }
                guard !Task.isCancelled, generation == token else { return }
                loadingIndex = nil
                playingIndex = index
            } catch is CancellationError {
                // A new choice or leaving the screen cancelled this preview.
            } catch {
                guard generation == token else { return }
                loadingIndex = nil
                playingIndex = nil
                self.error = .keyPreviewFailed
            }
        }
    }

    func select(_ index: Int) {
        guard choices.options.indices.contains(index) else { return }
        selectedIndex = index
        selectedShift = choices.options[index].song.transposition.semitoneShift
        selectedSong = choices.options[index].song
    }

    func confirm() {
        guard !isRendering, let song = selectedSong else { return }
        stop()
        Contract.assertValid(song.validate())
        onChoose(song)
    }

    func stop() {
        rendering?.cancel(); rendering = nil
        request = UUID(); isRendering = false
        stopPreview()
    }

    private func stopPreview() {
        let ownsPlayback = playback != nil || isManualPreviewPlaying || playingIndex != nil || loadingIndex != nil
        isManualPreviewPlaying = false
        generation = UUID()
        playback?.cancel()
        playback = nil
        if ownsPlayback { previewer.stop() }
        playingIndex = nil
        loadingIndex = nil
    }
}
