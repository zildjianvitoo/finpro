//
//  CompingCompositionBuilder.swift
//  finpro
//
//  Builds the composition for the final cover (PRD §5.9). Owner: Zildjian Vito (ZV-07, ZV-08, ZV-09).
//
//  Timeline = song timeline. For every passed take, the take plus its handles goes on video
//  track A or B and vocal track A or B (alternating), so neighbouring takes overlap at each
//  boundary: the video dissolves and the vocals crossfade (equal power) over `crossfadeDuration`,
//  centred on the boundary. The instrumental has its own track from 0 to `endTime`.
//

import AVFoundation
import CoreMedia

nonisolated enum CompingError: Error, CustomStringConvertible {
    case invalidPlan([ContractViolation])
    case missingTrack(String)
    case exportUnavailable

    var description: String {
        switch self {
        case .invalidPlan(let violations): "Invalid comping plan:\n" + violations.map(\.description).joined(separator: "\n")
        case .missingTrack(let name): "Missing track: \(name)"
        case .exportUnavailable: "Export session could not be created"
        }
    }
}

nonisolated struct CompingCompositionBuilder {
    struct Output {
        let composition: AVMutableComposition
        let audioMix: AVMutableAudioMix
        let videoComposition: AVMutableVideoComposition
    }

    static let timescale: CMTimeScale = 48_000
    /// Linear pieces per crossfade ramp: AVAudioMix only ramps linearly, so the equal-power
    /// (sine/cosine) curve is approximated.
    static let fadeSteps = 8
    /// After a cut lined up on the face (`FaceCutAligner`), how long the incoming clip takes to ease
    /// back to its own framing; slow enough to read as a gentle camera move.
    static let alignmentSettle: TimeInterval = 0.8

    var aligner = FaceCutAligner()

    /// The video and audio track of one recording pass's raw file.
    private struct Source {
        /// Kept alive while building: a track only holds its asset weakly.
        let asset: AVURLAsset
        let video: AVAssetTrack
        let audio: AVAssetTrack
    }

    /// Loads the raw file of every pass a take comes from.
    private func sources(for plan: CompingCompositionPlan) async throws -> [Int: Source] {
        var sources: [Int: Source] = [:]
        for pass in Set(plan.validTakes.map(\.recordingPass)).sorted() {
            guard plan.rawVideoURLs.indices.contains(pass) else { throw CompingError.missingTrack("raw video of pass \(pass)") }
            let raw = AVURLAsset(url: plan.rawVideoURLs[pass])
            guard let video = try await raw.loadTracks(withMediaType: .video).first else {
                throw CompingError.missingTrack("raw video of pass \(pass)")
            }
            guard let audio = try await raw.loadTracks(withMediaType: .audio).first else {
                throw CompingError.missingTrack("raw audio of pass \(pass)")
            }
            sources[pass] = Source(asset: raw, video: video, audio: audio)
        }
        return sources
    }

    func build(_ plan: CompingCompositionPlan) async throws -> Output {
        let sources = try await sources(for: plan)
        // Every pass is filmed by the same camera setup, so the first take's file sets orientation and size.
        guard let first = plan.validTakes.first, let rawVideo = sources[first.recordingPass]?.video else {
            throw CompingError.missingTrack("raw video")
        }
        let instrumentalAsset = AVURLAsset(url: plan.instrumentalURL)
        guard let instrumental = try await instrumentalAsset.loadTracks(withMediaType: .audio).first else {
            throw CompingError.missingTrack("instrumental")
        }

        let composition = AVMutableComposition()
        guard let videoA = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let videoB = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let vocalA = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
              let vocalB = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
              let instrumentalTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw CompingError.missingTrack("composition track")
        }
        let (rawTransform, naturalSize, frameRate, formats) = try await rawVideo.load(.preferredTransform, .naturalSize,
                                                                                     .nominalFrameRate, .formatDescriptions)
        let transform = Self.anchored(rawTransform, naturalSize: naturalSize)
        let videoTracks = [videoA, videoB]
        let vocalTracks = [vocalA, vocalB]
        let vocalParameters = vocalTracks.map { track in
            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.setVolume(0, at: .zero)
            return parameters
        }

        let handle = plan.crossfadeDuration.seconds
        let halfFade = handle / 2
        let lastIndex = plan.validTakes.count - 1

        for (position, take) in plan.validTakes.enumerated() {
            let segment = plan.segments[take.segmentIndex]
            guard let source = sources[take.recordingPass] else { throw CompingError.missingTrack("raw video of pass \(take.recordingPass)") }
            // Where the segment itself starts inside the raw file (the take range includes the handles).
            let segmentStartInRaw = take.videoTimeRange.start.seconds + handle

            // No handle before the first take (song starts at 0) or after the last one (song ends at endTime).
            let lead = position == 0 ? 0 : handle
            let tail = position == lastIndex ? 0 : handle
            let range = CMTimeRange(start: time(segmentStartInRaw - lead), duration: time(segment.audioDuration + lead + tail))
            try videoTracks[position % 2].insertTimeRange(range, of: source.video, at: time(segment.audioStartTime - lead))
            try vocalTracks[position % 2].insertTimeRange(range, of: source.audio, at: time(segment.audioStartTime - lead))

            // Crossfade window is centered on each boundary.
            let parameters = vocalParameters[position % 2]
            if position == 0 {
                parameters.setVolume(plan.vocalGain, at: .zero)
            } else {
                fade(parameters, in: true, gain: plan.vocalGain, from: segment.audioStartTime - halfFade, duration: handle)
            }
            if position < lastIndex {
                fade(parameters, in: false, gain: plan.vocalGain, from: segment.audioEndTime - halfFade, duration: handle)
            }
        }

        let instrumentalDuration = try await instrumentalAsset.load(.duration).seconds
        try instrumentalTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: time(min(plan.endTime, instrumentalDuration))),
            of: instrumental, at: .zero)
        let instrumentalParameters = AVMutableAudioMixInputParameters(track: instrumentalTrack)
        instrumentalParameters.setVolume(plan.instrumentalGain, at: .zero)
        if plan.instrumentalFadeOut > 0 {
            let fadeStart = max(0, plan.endTime - plan.instrumentalFadeOut)
            instrumentalParameters.setVolumeRamp(fromStartVolume: plan.instrumentalGain, toEndVolume: 0,
                                                 timeRange: CMTimeRange(start: time(fadeStart), end: time(plan.endTime)))
        }

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = vocalParameters + [instrumentalParameters]
        let rendered = CGRect(origin: .zero, size: naturalSize).applying(transform)
        let renderSize = CGSize(width: abs(rendered.width), height: abs(rendered.height))
        let corrections = await aligner.corrections(plan: plan, renderSize: renderSize)
        let videoComposition = dissolves(plan, tracks: videoTracks, duration: composition.duration,
                                         transform: transform, renderSize: renderSize, frameRate: frameRate,
                                         corrections: corrections)
        // Keep the recording's own colour space (camera files are tagged, e.g. BT.709 or HLG), so the
        // dissolve doesn't convert every frame on export.
        if let extensions = formats.first.flatMap({ CMFormatDescriptionGetExtensions($0) as? [String: Any] }) {
            videoComposition.colorPrimaries = extensions[kCVImageBufferColorPrimariesKey as String] as? String
            videoComposition.colorTransferFunction = extensions[kCVImageBufferTransferFunctionKey as String] as? String
            videoComposition.colorYCbCrMatrix = extensions[kCVImageBufferYCbCrMatrixKey as String] as? String
        }
        return Output(composition: composition, audioMix: audioMix, videoComposition: videoComposition)
    }

    /// One take at a time, and a dissolve (outgoing take fading out over the incoming one) centred on
    /// every boundary. The raw transform keeps the portrait orientation and mirroring. A take with a
    /// face correction starts lined up with the take before it, holds that over the dissolve, and
    /// eases back to its own framing.
    private func dissolves(_ plan: CompingCompositionPlan, tracks: [AVMutableCompositionTrack], duration: CMTime,
                           transform: CGAffineTransform, renderSize: CGSize, frameRate: Float,
                           corrections: [Int: CGAffineTransform]) -> AVMutableVideoComposition {
        let halfFade = plan.crossfadeDuration.seconds / 2
        let boundaries = plan.validTakes.dropLast().map { plan.segments[$0.segmentIndex].audioEndTime }
        func layer(_ position: Int) -> AVMutableVideoCompositionLayerInstruction {
            let instruction = AVMutableVideoCompositionLayerInstruction(assetTrack: tracks[position % 2])
            guard let correction = corrections[position] else {
                instruction.setTransform(transform, at: .zero)
                return instruction
            }
            let segment = plan.segments[plan.validTakes[position].segmentIndex]
            let aligned = transform.concatenating(correction)
            let settle = min(Self.alignmentSettle, segment.audioDuration / 2)
            instruction.setTransform(aligned, at: .zero)
            instruction.setTransformRamp(fromStart: aligned, toEnd: transform,
                                         timeRange: CMTimeRange(start: time(segment.audioStartTime + halfFade), duration: time(settle)))
            return instruction
        }
        var instructions: [AVMutableVideoCompositionInstruction] = []
        func add(_ range: CMTimeRange, _ layers: [AVMutableVideoCompositionLayerInstruction]) {
            guard range.duration > .zero else { return }
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = range
            instruction.layerInstructions = layers
            instructions.append(instruction)
        }
        var start = CMTime.zero
        for (position, boundary) in boundaries.enumerated() {
            let fadeStart = time(boundary - halfFade), fadeEnd = time(boundary + halfFade)
            add(CMTimeRange(start: start, end: fadeStart), [layer(position)])
            let outgoing = layer(position)
            outgoing.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 0, timeRange: CMTimeRange(start: fadeStart, end: fadeEnd))
            add(CMTimeRange(start: fadeStart, end: fadeEnd), [outgoing, layer(position + 1)])
            start = fadeEnd
        }
        add(CMTimeRange(start: start, end: duration), [layer(boundaries.count)])

        let video = AVMutableVideoComposition()
        video.instructions = instructions
        video.renderSize = renderSize
        video.frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate > 0 ? frameRate.rounded() : 30))
        return video
    }

    /// The raw transform moved so the oriented frame starts at (0, 0). Players do this on their own,
    /// a video composition doesn't: a 90° rotation without its translation (as written for cameras
    /// that deliver landscape frames) would draw every frame outside the render area, all black.
    static func anchored(_ transform: CGAffineTransform, naturalSize: CGSize) -> CGAffineTransform {
        let placed = CGRect(origin: .zero, size: naturalSize).applying(transform)
        return transform.concatenating(CGAffineTransform(translationX: -placed.minX, y: -placed.minY))
    }

    /// Equal-power fade (sine in / cosine out), as `fadeSteps` linear ramps.
    private func fade(_ parameters: AVMutableAudioMixInputParameters, in fadeIn: Bool, gain: Float,
                      from start: TimeInterval, duration: TimeInterval) {
        func level(_ step: Int) -> Float {
            let x = Double(step) / Double(Self.fadeSteps)
            return gain * Float(fadeIn ? sin(x * .pi / 2) : cos(x * .pi / 2))
        }
        let step = duration / Double(Self.fadeSteps)
        for index in 0..<Self.fadeSteps {
            parameters.setVolumeRamp(fromStartVolume: level(index), toEndVolume: level(index + 1),
                                     timeRange: CMTimeRange(start: time(start + Double(index) * step), duration: time(step)))
        }
    }

    private func time(_ seconds: TimeInterval) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: Self.timescale)
    }
}
