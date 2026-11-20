//
//  SavedSong.swift
//  finpro
//

import Foundation

nonisolated struct SavedSong: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var title: String
    let createdAt: Date
    let filename: String
    let duration: TimeInterval
    let waveform: [Float]
    let sourceTitle: String
    let artist: String?
    var selectionStart: TimeInterval
    var selectionLength: TimeInterval
    var lyrics: SongLyrics?
    /// The song's artist: from Shazam, else the file. Nil in songs saved before it existed.
    var displayArtist: String? = nil
    /// Shazam was asked about this song and answered (a match or not); it is not asked again.
    var isRecognitionDone: Bool? = nil
    /// The user renamed the song; a recognized name never replaces theirs.
    var isRenamedByUser: Bool? = nil
}
