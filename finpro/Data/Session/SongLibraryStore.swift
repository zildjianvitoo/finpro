//
//  SongLibraryStore.swift
//  finpro
//

import Foundation

/// Audio is copied out of the temporary import folder before a song is saved.
/// Relative filenames survive app-container changes and device restores.
nonisolated struct SongLibraryStore: Sendable {
    struct Snapshot: Codable, Sendable {
        var songs: [SavedSong] = []
        var nextNumber = 1
    }
    let directory: URL
    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("SongLibrary", isDirectory: true)) {
        self.directory = directory
    }
    func url(for song: SavedSong) -> URL { directory.appendingPathComponent(song.filename) }
    func load() throws -> Snapshot {
        let manifest = directory.appendingPathComponent("songs.json")
        guard FileManager.default.fileExists(atPath: manifest.path) else { return Snapshot() }
        return try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: manifest))
    }
    func persist(_ snapshot: Snapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: directory.appendingPathComponent("songs.json"), options: .atomic)
    }
    func copyAudio(_ source: URL, id: UUID) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = id.uuidString + "." + (source.pathExtension.isEmpty ? "audio" : source.pathExtension)
        try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(filename))
        return filename
    }
    func removeAudio(_ song: SavedSong) { try? FileManager.default.removeItem(at: url(for: song)) }
}
