//
//  SavedCover.swift
//  finpro
//

import Foundation

nonisolated struct SavedCover: Identifiable, Codable, Sendable {
    let id: UUID
    let title: String
    let date: Date
    let duration: TimeInterval
    let isDraft: Bool
    let filename: String
}
