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
    private(set) var error: UserFacingError?
    @ObservationIgnored private let previewer: any AudioPreviewing
    @ObservationIgnored private var playback: Task<Void, Never>?

    init(library: SongLibrary, previewer: any AudioPreviewing) {
        self.library = library
        self.previewer = previewer
    }
    var songs: [SavedSong] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return library.songs.filter { term.isEmpty || $0.title.localizedCaseInsensitiveContains(term) }
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
        if playingID == song.id { stop(); return }
        stop()
        expandedID = song.id
        do { try previewer.play(library.audio(for: song).url, from: 0) }
        catch { self.error = .keyPreviewFailed; return }
        error = nil
        playingID = song.id
        playbackTime = 0
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
    func delete(_ ids: Set<UUID>) {
        if let playingID, ids.contains(playingID) { stop() }
        library.delete(ids)
        selectedIDs = selectedIDs.intersection(Set(library.songs.map(\.id)))
        if library.error == nil { selecting = false }
    }
    func stop() {
        let ownsPlayback = playback != nil || playingID != nil
        playback?.cancel(); playback = nil
        if ownsPlayback { previewer.stop() }
        playingID = nil; playbackTime = 0
    }
}
