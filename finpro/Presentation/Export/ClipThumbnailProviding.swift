//
//  ClipThumbnailProviding.swift
//  finpro
//
//  Presentation-side capability for the final result screens: a still frame per clip of the
//  exported cover. Not a Domain contract. Owner: Zildjian Vito (ZV-13).
//

import CoreGraphics
import Foundation

nonisolated protocol ClipThumbnailProviding: Sendable {
    /// One frame per time (seconds on the cover's timeline); nil where none could be read.
    func thumbnails(for url: URL, at times: [TimeInterval]) async -> [CGImage?]
}
