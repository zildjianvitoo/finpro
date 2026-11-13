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
}
