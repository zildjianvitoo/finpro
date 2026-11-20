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
    /// iOS stopped the export (the video hardware was busy or the app left the foreground) and
    /// the retries did not get through.
    case exportInterrupted

    var description: String {
        switch self {
        case .invalidPlan(let violations): "Invalid comping plan:\n" + violations.map(\.description).joined(separator: "\n")
        case .missingTrack(let name): "Missing track: \(name)"
        case .exportUnavailable: "Export session could not be created"
        case .exportInterrupted: "The export was interrupted. Keep Verca open and tap Try Again."
        }
    }
}

nonisolated struct CompingCompositionBuilder {
    struct Output {
        let preparedTracks: [PreparedMixTrack]
        var composition: AVMutableComposition
        var audioMix: AVMutableAudioMix
        /// Overall level for the given slider levels, so the mix never clips.
        var previewGainScale: (Float, Float) -> Float = { _, _ in 1 }
        /// The preview's volume curves per audio track, at slider level 1 and without `previewGainScale`.
        var previewEnvelopes: [CMPersistentTrackID: PreviewEnvelope] = [:]
        let makeMix: (Float, Float) -> AVMutableAudioMix
        let videoComposition: AVMutableVideoComposition
        let vocalTrackIDs: Set<CMPersistentTrackID>
        let musicTrackID: CMPersistentTrackID

        /// Build the playback/export asset without muted sources. Track IDs of the remaining
        /// sources are preserved, so the gain ramps and video instructions still apply.
        func applyingVolumes(vocals: Float, music: Float) throws -> Output {
            var output = self
            output.audioMix = makeMix(vocals, music)
            guard vocals == 0 || music == 0 else { return output }
            guard let filtered = composition.mutableCopy() as? AVMutableComposition else {
                throw CompingError.exportUnavailable
            }
            var muted = vocals == 0 ? vocalTrackIDs : []
            if music == 0 { muted.insert(musicTrackID) }
            for id in muted {
                if let track = filtered.track(withTrackID: id) { filtered.removeTrack(track) }
            }
            output.audioMix.inputParameters = output.audioMix.inputParameters.filter { !muted.contains($0.trackID) }
            output.composition = filtered
            return output
        }
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
        var prepared: [PreparedMixTrack] = []
        var insertTimes: [TimeInterval] = []
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
            let core = CMTimeRange(start: time(segmentStartInRaw), duration: time(segment.audioDuration))
            let audio = try await PreparedMixTrack(asset: source.asset, track: source.audio, range: range, core: core)
            prepared.append(audio)
            insertTimes.append(segment.audioStartTime - lead)
            try vocalTracks[position % 2].insertTimeRange(CMTimeRange(start: .zero, duration: range.duration),
                                                        of: audio.track, at: time(segment.audioStartTime - lead))
        }

        let levels = prepared.map(\.level).filter { $0 > 0 }.sorted()
        let reference = levels.isEmpty ? 0 : levels[levels.count / 2]
        let corrections = prepared.map { $0.level > 0 ? min(4, max(0.25, reference / $0.level)) : 1 }
        let musicDuration = try await instrumentalAsset.load(.duration)
        let musicRange = CMTimeRange(start: .zero, duration: min(time(plan.endTime), musicDuration))
        let music = try await PreparedMixTrack(asset: instrumentalAsset, track: instrumental, range: musicRange, core: musicRange)
        try instrumentalTrack.insertTimeRange(musicRange, of: music.track, at: .zero)
        // Upper bound of the mixed signal in every 10 ms of the song: the loudest sample of each
        // source there, added up (the fades only lower a source). Unlike one peak per source, this
        // knows where the voice and the music are actually loud, so the mix keeps its level and
        // only turns down when the chosen levels would really clip.
        let block = PreparedMixTrack.blockDuration
        let ends = zip(prepared, insertTimes).map { $1 + Double($0.blockPeaks.count) * block }
        let blockCount = Int((max(plan.endTime, ends.max() ?? 0) / block).rounded(.up)) + 2
        func envelope(_ track: PreparedMixTrack, at start: TimeInterval) -> [Float] {
            var result = [Float](repeating: 0, count: blockCount)
            for (index, peak) in track.blockPeaks.enumerated() where peak > 0 {
                let from = start + Double(index) * block
                // A source block straddles two song blocks unless it lines up exactly: count it in both.
                let first = max(0, Int((from / block).rounded(.down)))
                let last = min(blockCount - 1, Int(((from + block) / block).rounded(.down)))
                guard first <= last else { continue }
                for slot in first...last { result[slot] = max(result[slot], peak) }
            }
            return result
        }
        var vocalEnvelope = [Float](repeating: 0, count: blockCount)
        for (position, track) in prepared.enumerated() {
            for (slot, peak) in envelope(track, at: insertTimes[position]).enumerated() where peak > 0 {
                vocalEnvelope[slot] += peak * corrections[position]
            }
        }
        let musicEnvelope = envelope(music, at: 0)
        func scale(_ vocals: Float, _ backing: Float) -> Float {
            var peak: Float = 0
            for slot in 0..<blockCount {
                peak = max(peak, vocals * vocalEnvelope[slot] + backing * musicEnvelope[slot])
            }
            return min(1, 0.97 / max(peak, 0.001))
        }
        func makeMix(_ vocals: Float, _ backing: Float) -> AVMutableAudioMix {
            let headroom = scale(vocals, backing) / PreparedMixTrack.reserve
            let vocalParameters = vocalTracks.map { track in
                let parameters = AVMutableAudioMixInputParameters(track: track)
                parameters.setVolume(0, at: .zero)
                return parameters
            }

            for (position, take) in plan.validTakes.enumerated() where vocals > 0 {
                let segment = plan.segments[take.segmentIndex]
                let gain = vocals * corrections[position] * headroom
                // Crossfade window is centered on each boundary.
                let parameters = vocalParameters[position % 2]
                if position == 0 {
                    parameters.setVolume(gain, at: .zero)
                } else {
                    fade(parameters, in: true, gain: gain, from: segment.audioStartTime - halfFade, duration: handle)
                }
                if position < lastIndex {
                    fade(parameters, in: false, gain: gain, from: segment.audioEndTime - halfFade, duration: handle)
                }
            }

            let instrumentalParameters = AVMutableAudioMixInputParameters(track: instrumentalTrack)
            instrumentalParameters.setVolume(backing * headroom, at: .zero)
            if backing > 0, plan.instrumentalFadeOut > 0 {
                let fadeStart = max(0, plan.endTime - plan.instrumentalFadeOut)
                instrumentalParameters.setVolumeRamp(fromStartVolume: backing * headroom, toEndVolume: 0,
                                                     timeRange: CMTimeRange(start: time(fadeStart), end: time(plan.endTime)))
            }

            let audioMix = AVMutableAudioMix()
            audioMix.inputParameters = vocalParameters + [instrumentalParameters]
            return audioMix
        }
        var envelopes: [CMPersistentTrackID: PreviewEnvelope] = [:]
        for (index, track) in vocalTracks.enumerated() {
            let parts = plan.validTakes.enumerated().filter { $0.offset % 2 == index }.map { position, take in
                let segment = plan.segments[take.segmentIndex]
                return PreviewEnvelope.Part(gain: corrections[position] / PreparedMixTrack.reserve,
                                            fadeInStart: position == 0 ? nil : segment.audioStartTime - halfFade,
                                            fadeOutStart: position < lastIndex ? segment.audioEndTime - halfFade : nil)
            }
            envelopes[track.trackID] = PreviewEnvelope(parts: parts, crossfade: handle)
        }
        var musicCurve = PreviewEnvelope(parts: [.init(gain: 1 / PreparedMixTrack.reserve, fadeInStart: nil, fadeOutStart: nil)],
                                            crossfade: handle)
        if plan.instrumentalFadeOut > 0 {
            musicCurve.fadeOutStart = max(0, plan.endTime - plan.instrumentalFadeOut)
            musicCurve.fadeOutEnd = plan.endTime
        }
        envelopes[instrumentalTrack.trackID] = musicCurve

        let rendered = CGRect(origin: .zero, size: naturalSize).applying(transform)
        let renderSize = CGSize(width: abs(rendered.width), height: abs(rendered.height))
        let alignments = await aligner.corrections(plan: plan, renderSize: renderSize)
        let videoComposition = dissolves(plan, tracks: videoTracks, duration: composition.duration,
                                         transform: transform, renderSize: renderSize, frameRate: frameRate,
                                         corrections: alignments)
        // Keep the recording's own colour space (camera files are tagged, e.g. BT.709 or HLG), so the
        // dissolve doesn't convert every frame on export.
        if let extensions = formats.first.flatMap({ CMFormatDescriptionGetExtensions($0) as? [String: Any] }) {
            videoComposition.colorPrimaries = extensions[kCVImageBufferColorPrimariesKey as String] as? String
            videoComposition.colorTransferFunction = extensions[kCVImageBufferTransferFunctionKey as String] as? String
            videoComposition.colorYCbCrMatrix = extensions[kCVImageBufferYCbCrMatrixKey as String] as? String
        }
        return Output(preparedTracks: prepared + [music], composition: composition, audioMix: makeMix(plan.vocalGain, plan.instrumentalGain), previewGainScale: { scale($0, $1) }, previewEnvelopes: envelopes, makeMix: makeMix, videoComposition: videoComposition,
                      vocalTrackIDs: Set(vocalTracks.map(\.trackID)), musicTrackID: instrumentalTrack.trackID)
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
