//
//  FaceCutAligner.swift
//  finpro
//
//  Smooths the cut between clips from different recording passes (a retake or continue next to
//  the session): Vision finds the singer's face at the end of the outgoing clip and the start of
//  the incoming one, and the incoming clip is shifted and zoomed so the face is where it was. The
//  builder holds that framing over the dissolve, then eases back to the clip's own framing.
//  Owner: Zildjian Vito.
//

import AVFoundation
import CoreGraphics
import Vision

nonisolated struct FaceCutAligner {
    /// A face in the rendered (portrait) frame: centre and height in points, top-left origin.
    struct Face: Equatable {
        let center: CGPoint
        let height: CGFloat
    }

    /// The most the incoming clip is zoomed in to match: more would look like a different shot.
    static let maximumZoom: CGFloat = 1.15
    /// Below these, the clips already line up and the cut is left as it is.
    static let minimumShift: CGFloat = 0.01
    static let minimumZoom: CGFloat = 0.02
    private static let frameSize = CGSize(width: 720, height: 1280)

    /// Correction for each take position that starts a new recording pass, in render coordinates
    /// (applied after the raw transform). Positions without a usable face on both sides are left out.
    func corrections(plan: CompingCompositionPlan, renderSize: CGSize) async -> [Int: CGAffineTransform] {
        let handle = plan.crossfadeDuration.seconds
        var result: [Int: CGAffineTransform] = [:]
        for position in plan.validTakes.indices.dropFirst() {
            let outgoing = plan.validTakes[position - 1], incoming = plan.validTakes[position]
            guard outgoing.recordingPass != incoming.recordingPass,
                  plan.rawVideoURLs.indices.contains(outgoing.recordingPass),
                  plan.rawVideoURLs.indices.contains(incoming.recordingPass) else { continue }
            async let before = face(in: plan.rawVideoURLs[outgoing.recordingPass],
                                    at: outgoing.videoTimeRange.end.seconds - handle, renderSize: renderSize)
            async let after = face(in: plan.rawVideoURLs[incoming.recordingPass],
                                   at: incoming.videoTimeRange.start.seconds + handle, renderSize: renderSize)
            if let target = await before, let current = await after,
               let correction = Self.correction(moving: current, onto: target, renderSize: renderSize) {
                result[position] = correction
            }
        }
        return result
    }

    /// The zoom-and-shift that puts `current` over `target`, about the frame centre. It only zooms in
    /// (up to `maximumZoom`) and never shifts so far that an edge of the frame shows. nil when the
    /// change would be too small to matter.
    static func correction(moving current: Face, onto target: Face, renderSize size: CGSize) -> CGAffineTransform? {
        guard current.height > 0, size.width > 0, size.height > 0 else { return nil }
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        func shift(at scale: CGFloat) -> CGVector {
            CGVector(dx: target.center.x - centre.x - scale * (current.center.x - centre.x),
                     dy: target.center.y - centre.y - scale * (current.center.y - centre.y))
        }
        // Zoom to match the face size, then enough more to cover the shift, within the limit. Zooming
        // moves the face too, so the cover zoom is refined a few times (it converges, as the face is
        // inside the frame).
        let sizeZoom = min(max(target.height / current.height, 1), maximumZoom)
        var scale = sizeZoom
        for _ in 0..<8 {
            let wanted = shift(at: scale)
            let coverZoom = 1 + 2 * max(abs(wanted.dx) / size.width, abs(wanted.dy) / size.height)
            scale = min(max(sizeZoom, coverZoom), maximumZoom)
        }
        // Zooming by `scale` leaves (scale - 1) / 2 of the frame to spare on each side.
        let spareX = (scale - 1) * size.width / 2, spareY = (scale - 1) * size.height / 2
        let raw = shift(at: scale)
        let dx = min(max(raw.dx, -spareX), spareX), dy = min(max(raw.dy, -spareY), spareY)
        guard scale - 1 >= minimumZoom || abs(dx) / size.width >= minimumShift || abs(dy) / size.height >= minimumShift else {
            return nil
        }
        return CGAffineTransform(translationX: -centre.x, y: -centre.y)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: centre.x + dx, y: centre.y + dy))
    }

    /// The largest face in one frame of a raw file, as it is rendered (orientation applied).
    private func face(in url: URL, at seconds: TimeInterval, renderSize: CGSize) async -> Face? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = Self.frameSize
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        guard let image = try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image else { return nil }
        let request = VNDetectFaceRectanglesRequest()
        guard (try? VNImageRequestHandler(cgImage: image).perform([request])) != nil,
              let box = request.results?.max(by: { $0.boundingBox.height < $1.boundingBox.height })?.boundingBox else { return nil }
        // Vision boxes are normalized with a bottom-left origin.
        return Face(center: CGPoint(x: box.midX * renderSize.width, y: (1 - box.midY) * renderSize.height),
                    height: box.height * renderSize.height)
    }
}
