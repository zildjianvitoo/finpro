//
//  SongRecognizing.swift
//  finpro
//
//  Names an imported song (title and artist) from its sound, so songs from files with missing or
//  messy names still get their real name, and the lyrics search uses it. Implemented by
//  ShazamSongRecognizer (Data).
//

import Foundation

nonisolated struct RecognizedSong: Equatable, Sendable {
    let title: String
    let artist: String?
}

nonisolated enum SongRecognitionError: Error, Equatable {
    /// No connection, timeout, or the service is not set up for this app; try again another time.
    case unavailable
}

nonisolated protocol SongRecognizing: Sendable {
    /// The song in the file, or nil when the service does not know it.
    func recognize(fileAt url: URL, duration: TimeInterval) async throws -> RecognizedSong?
}
