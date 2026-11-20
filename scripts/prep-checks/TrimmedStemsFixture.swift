//
//  TrimmedStemsFixture.swift
//  prep-checks
//
//  Test stand-in for stem separation: the stems are given already separated, and are only
//  trimmed (so they start at t = 0, as the contract requires).
//

import AVFoundation

nonisolated struct TrimmedStemsFixture: StemSeparationRepository {
    let mixURL: URL
    let vocalURL: URL
    let instrumentalURL: URL
    let directory: URL

    func separateStems(from audioURL: URL, trimRange: ClosedRange<TimeInterval>) async throws -> SeparatedStems {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return SeparatedStems(mixURL: try trim(mixURL, trimRange, "mix.wav"),
                              vocalGuideURL: try trim(vocalURL, trimRange, "vocalGuide.wav"),
                              instrumentalURL: try trim(instrumentalURL, trimRange, "instrumental.wav"),
                              method: .bundled)
    }

    private func trim(_ url: URL, _ range: ClosedRange<TimeInterval>, _ name: String) throws -> URL {
        let input = try AVAudioFile(forReading: url)
        let rate = input.processingFormat.sampleRate
        let start = AVAudioFramePosition(range.lowerBound * rate)
        let frames = AVAudioFrameCount((range.upperBound - range.lowerBound) * rate)
        input.framePosition = start
        let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: frames)!
        try input.read(into: buffer, frameCount: frames)
        let output = directory.appendingPathComponent(name)
        try AVAudioFile(forWriting: output, settings: input.processingFormat.settings).write(from: buffer)
        return output
    }
}
