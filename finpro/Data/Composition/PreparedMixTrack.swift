import AVFoundation

/// Float PCM with enough gain reserved for both take matching and the preview controls.
/// The composition retains the file owner through playback or export.
nonisolated final class PreparedMixTrack {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
    let asset: AVURLAsset
    let track: AVAssetTrack
    let level: Float
    let peak: Float
    static let reserve: Float = 8

    init(asset source: AVAsset, track input: AVAssetTrack, range: CMTimeRange, core: CMTimeRange) async throws {
        let destination = url
        var succeeded = false
        defer { if !succeeded { try? FileManager.default.removeItem(at: destination) } }
        let reader = try AVAssetReader(asset: source)
        reader.timeRange = range
        let output = AVAssetReaderTrackOutput(track: input, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsNonInterleaved: false
        ])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? CompingError.missingTrack("audio samples") }
        var file: AVAudioFile?
        var levels: [Float] = []
        var maximum: Float = 0
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let description = sample.formatDescription else { throw CompingError.missingTrack("PCM description") }
            let format = AVAudioFormat(cmAudioFormatDescription: description)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sample.numSamples))
            else { throw CompingError.missingTrack("PCM format") }
            buffer.frameLength = buffer.frameCapacity
            guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(buffer.frameLength), into: buffer.mutableAudioBufferList) == noErr,
                  let values = buffer.floatChannelData?[0] else { throw CompingError.missingTrack("PCM samples") }
            let count = Int(buffer.frameLength) * Int(format.channelCount)
            var energy: Float = 0
            for i in 0..<count {
                let value = values[i]
                maximum = max(maximum, abs(value))
                energy += value * value
                values[i] = value * Self.reserve
            }
            if core.containsTime(sample.presentationTimeStamp), count > 0 {
                levels.append(sqrt(energy / Float(count)))
            }
            if file == nil {
                file = try AVAudioFile(forWriting: destination, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: true)
            }
            try file?.write(from: buffer)
        }
        guard reader.status == .completed else { throw reader.error ?? CompingError.exportUnavailable }
        file = nil
        let gate = max(0.003, (levels.max() ?? 0) * 0.08)
        let active = levels.filter { $0 >= gate }.sorted()
        level = active.isEmpty ? 0 : active[active.count / 2]
        peak = maximum
        asset = AVURLAsset(url: destination)
        guard let audio = try await asset.loadTracks(withMediaType: .audio).first else { throw CompingError.missingTrack("prepared audio") }
        track = audio
        succeeded = true
    }

    deinit { try? FileManager.default.removeItem(at: url) }
}
