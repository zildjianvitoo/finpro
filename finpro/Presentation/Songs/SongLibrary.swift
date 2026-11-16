//
//  SongLibrary.swift
//  finpro
//

import Foundation
import Observation

@Observable
final class SongLibrary {
    private(set) var songs: [SavedSong] = []
    private(set) var error: UserFacingError?
    @ObservationIgnored private let store: SongLibraryStore
    @ObservationIgnored private var nextNumber = 1
    @ObservationIgnored private var loadFailed = false

    init(store: SongLibraryStore = SongLibraryStore()) {
        self.store = store
        do {
            let snapshot = try store.load()
            songs = snapshot.songs
            nextNumber = snapshot.nextNumber
        } catch {
            loadFailed = true
            self.error = .songLibraryFailed
        }
    }
    /// The saved song made from the same file, if any: picking a file again opens its song
    /// instead of adding a copy.
    func song(matching audio: ImportedAudio) -> SavedSong? {
        let size = SongLibraryStore.fileSize(audio.url)
        return songs.first {
            abs($0.duration - audio.duration) < Self.sameDurationTolerance && $0.sourceTitle == audio.title
                && $0.artist == audio.artist && size != nil && SongLibraryStore.fileSize(store.url(for: $0)) == size
        }
    }
    /// Durations of one file read twice differ by far less than this.
    private static let sameDurationTolerance: TimeInterval = 0.05

    func audio(for song: SavedSong) -> ImportedAudio {
        ImportedAudio(url: store.url(for: song), name: song.title, duration: song.duration,
                      waveform: song.waveform, title: song.sourceTitle, artist: song.artist)
    }
    @discardableResult
    func save(audio: ImportedAudio, existingID: UUID?, start: TimeInterval,
              length: TimeInterval, lyrics: SongLyrics?) throws -> SavedSong {
        guard !loadFailed, start.isFinite, length.isFinite, start >= 0,
              length >= ImportSongViewModel.minimumLength,
              length <= ImportSongViewModel.maximumLength,
              start + length <= audio.duration + 0.001 else {
            error = .songLibraryFailed
            throw UserFacingError.songLibraryFailed
        }
        var updated = songs
        let existing = existingID.flatMap { id in updated.firstIndex { $0.id == id } }
        var added: SavedSong?
        do {
            let song: SavedSong
            if let index = existing {
                var record = updated[index]
                record.selectionStart = start
                record.selectionLength = length
                record.lyrics = lyrics ?? record.lyrics
                updated[index] = record
                song = record
            } else {
                let id = UUID()
                let filename = try store.copyAudio(audio.url, id: id)
                let title = audio.title.trimmingCharacters(in: .whitespaces)
                song = SavedSong(id: id, title: title.isEmpty ? "Song \(nextNumber)" : title, createdAt: Date(), filename: filename,
                                 duration: audio.duration, waveform: audio.waveform, sourceTitle: audio.title,
                                 artist: audio.artist, selectionStart: start, selectionLength: length, lyrics: lyrics,
                                 displayArtist: audio.artist)
                added = song
                updated.insert(song, at: 0)
            }
            let number = nextNumber + (existing == nil ? 1 : 0)
            try store.persist(.init(songs: updated, nextNumber: number))
            songs = updated
            nextNumber = number
            error = nil
            return song
        } catch {
            if let added { store.removeAudio(added) }
            self.error = .songLibraryFailed
            throw error
        }
    }
    func rename(_ id: UUID, title: String) {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, let index = songs.firstIndex(where: { $0.id == id }) else { return }
        var updated = songs
        updated[index].title = value
        updated[index].isRenamedByUser = true
        commit(updated)
    }
    /// Shazam answered for a saved song: use its name (unless the user renamed the song) and don't
    /// ask again. Returns the song as saved.
    @discardableResult
    func applyRecognition(_ id: UUID, song recognized: RecognizedSong?) -> SavedSong? {
        guard let index = songs.firstIndex(where: { $0.id == id }) else { return nil }
        var updated = songs
        updated[index].isRecognitionDone = true
        if let recognized, updated[index].isRenamedByUser != true {
            updated[index].title = recognized.title
            updated[index].displayArtist = recognized.artist ?? updated[index].displayArtist
        }
        guard updated[index] != songs[index] else { return songs[index] }
        return commit(updated) ? updated[index] : songs[index]
    }
    func delete(_ ids: Set<UUID>) {
        let removed = songs.filter { ids.contains($0.id) }
        if commit(songs.filter { !ids.contains($0.id) }) { removed.forEach(store.removeAudio) }
    }
    @discardableResult private func commit(_ updated: [SavedSong]) -> Bool {
        guard !loadFailed else { return false }
        do {
            try store.persist(.init(songs: updated, nextNumber: nextNumber))
            songs = updated
            error = nil
            return true
        } catch { self.error = .songLibraryFailed; return false }
    }
    func clearError() { error = nil }
}
