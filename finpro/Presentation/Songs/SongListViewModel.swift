//
//  SongListViewModel.swift
//  finpro
//

import Foundation
import Observation

@Observable
final class SongListViewModel {
    let library: SongLibrary
    var query = ""
    private(set) var selecting = false
    private(set) var selectedIDs: Set<UUID> = []
    private(set) var expandedID: UUID?
    private(set) var playingID: UUID?
    private(set) var playbackTime: TimeInterval = 0
    private(set) var isScrubbing = false
    private(set) var error: UserFacingError?
    @ObservationIgnored private let previewer: any AudioPreviewing
    @ObservationIgnored private var playback: Task<Void, Never>?
    @ObservationIgnored private var wasPlayingBeforeScrub = false

    init(library: SongLibrary, previewer: any AudioPreviewing) {
        self.library = library
        self.previewer = previewer
    }
    var songs: [SavedSong] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return library.songs.filter {
            term.isEmpty
                || $0.title.localizedCaseInsensitiveContains(term)
                || ($0.displayArtist?.localizedCaseInsensitiveContains(term) ?? false)
                || ($0.artist?.localizedCaseInsensitiveContains(term) ?? false)
        }
    }
    func isPlaying(_ song: SavedSong) -> Bool {
        playingID == song.id || (isScrubbing && wasPlayingBeforeScrub && expandedID == song.id)
    }
    func toggleSelectionMode() {
        stop()
        selecting.toggle()
        selectedIDs = []
    }
    func select(_ id: UUID) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }
    func beginSelecting(_ id: UUID) {
        stop(); selecting = true; selectedIDs.insert(id)
    }
    func expand(_ id: UUID) {
        if expandedID != id { stop() }
        expandedID = id
    }
    /// Row taps play in place; choosing a section is a separate waveform action.
    func play(_ song: SavedSong) {
        guard playingID != song.id else { return }
        togglePlayback(song)
    }
    func togglePlayback(_ song: SavedSong) {
        if playingID == song.id { pause(); return }
        if expandedID != song.id { stop() }
        expandedID = song.id
        let start = playbackTime >= max(0, song.duration - 0.15) ? 0 : max(0, playbackTime)
        startPlayback(song, from: start)
    }
    func beginScrubbing(_ song: SavedSong) {
        guard !isScrubbing else { return }
        wasPlayingBeforeScrub = playingID == song.id
        isScrubbing = true
        expandedID = song.id
        pause()
    }
    func scrub(_ song: SavedSong, to fraction: Double) {
        let clamped = min(1, max(0, fraction))
        playbackTime = clamped * max(0, song.duration)
    }
    func endScrubbing(_ song: SavedSong) {
        guard isScrubbing else { return }
        isScrubbing = false
        let shouldResume = wasPlayingBeforeScrub
        wasPlayingBeforeScrub = false
        let target = clampedSeekTime(playbackTime, duration: song.duration)
        playbackTime = target
        if shouldResume { startPlayback(song, from: target) }
    }
    func seek(_ song: SavedSong, to time: TimeInterval) {
        let wasPlaying = playingID == song.id
        expandedID = song.id
        let target = clampedSeekTime(time, duration: song.duration)
        playbackTime = target
        if wasPlaying { startPlayback(song, from: target) }
    }
    func delete(_ ids: Set<UUID>) {
        if let playingID, ids.contains(playingID) { stop() }
        else if let expandedID, ids.contains(expandedID) { stop(); self.expandedID = nil }
        library.delete(ids)
        selectedIDs = selectedIDs.intersection(Set(library.songs.map(\.id)))
        if library.error == nil { selecting = false }
    }
    func stop() {
        pause()
        playbackTime = 0
        isScrubbing = false
        wasPlayingBeforeScrub = false
    }

    private func pause() {
        let ownsPlayback = playback != nil || playingID != nil
        playback?.cancel(); playback = nil
        if ownsPlayback { previewer.stop() }
        playingID = nil
    }

    private func startPlayback(_ song: SavedSong, from start: TimeInterval) {
        pause()
        do { try previewer.play(library.audio(for: song).url, from: start) }
        catch { self.error = .keyPreviewFailed; return }
        error = nil
        playingID = song.id
        playbackTime = start
        playback = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                guard !Task.isCancelled else { return }
                guard let time = previewer.currentTime else { break }
                playbackTime = time
            }
            if !Task.isCancelled { stop() }
        }
    }

    private func clampedSeekTime(_ time: TimeInterval, duration: TimeInterval) -> TimeInterval {
        min(max(0, time), max(0, duration - 0.05))
    }
}
