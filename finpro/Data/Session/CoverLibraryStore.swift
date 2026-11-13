//
//  CoverLibraryStore.swift
//  finpro
//

import Foundation

nonisolated struct CoverLibraryStore: Sendable {
    let directory: URL
    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Covers", isDirectory: true)) { self.directory = directory }
    func url(for cover: SavedCover) -> URL { directory.appendingPathComponent(cover.filename) }
    func load() throws -> [SavedCover] {
        let manifest = directory.appendingPathComponent("covers.json")
        guard FileManager.default.fileExists(atPath: manifest.path) else { return [] }
        return try JSONDecoder().decode([SavedCover].self, from: Data(contentsOf: manifest))
    }
    /// Deletes a cover's video file. Its record must already be gone from the manifest.
    func removeFile(of cover: SavedCover) {
        try? FileManager.default.removeItem(at: url(for: cover))
    }
    func save(_ cover: SavedCover, source: URL, records: [SavedCover]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: url(for: cover))
        do { try JSONEncoder().encode(records).write(to: directory.appendingPathComponent("covers.json"), options: .atomic) }
        catch { try? FileManager.default.removeItem(at: url(for: cover)); throw error }
    }
}
