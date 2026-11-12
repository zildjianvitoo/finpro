//
//  AVClipThumbnailProvider.swift
//  finpro
//
//  Reads still frames from the exported cover file. Owner: Zildjian Vito (ZV-13).
//

import AVFoundation
import CoreGraphics
import Foundation

nonisolated struct AVClipThumbnailProvider: ClipThumbnailProviding {
    /// Frames are shown small (a clip tile, or the poster), so there is no need for full size.
    static let maximumSize = CGSize(width: 360, height: 640)
    private static let timescale: CMTimeScale = 600

    func thumbnails(for url: URL, at times: [TimeInterval]) async -> [CGImage?] {
        // The fakes export returns a URL without writing a file.
        guard FileManager.default.fileExists(atPath: url.path) else { return times.map { _ in nil } }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = Self.maximumSize
        var frames: [CGImage?] = []
        for time in times {
            let frame = try? await generator.image(at: CMTime(seconds: time, preferredTimescale: Self.timescale)).image
            frames.append(frame)
        }
        return frames
    }
}
