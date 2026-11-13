//
//  CoverThumbnailViewModel.swift
//  finpro
//

import CoreGraphics
import Foundation
import Observation

@Observable
final class CoverThumbnailViewModel {
    let url: URL?
    let duration: TimeInterval
    private(set) var image: CGImage?
    @ObservationIgnored private let provider: any ClipThumbnailProviding
    @ObservationIgnored private var attempted = false

    init(url: URL?, duration: TimeInterval, provider: any ClipThumbnailProviding = AVClipThumbnailProvider()) {
        self.url = url
        self.duration = duration
        self.provider = provider
    }
    func load() async {
        guard !attempted, let url else { return }
        attempted = true
        let images = await provider.thumbnails(for: url, at: [max(0, duration / 2)])
        guard !Task.isCancelled else { attempted = false; return }
        image = images.first ?? nil
    }
}
