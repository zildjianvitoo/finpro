//
//  ShazamSongRecognizer.swift
//  finpro
//
//  Song title and artist from the Shazam catalog (ShazamKit). Only a signature of a short excerpt
//  (an audio fingerprint, not the audio itself) is sent to Apple. Needs the ShazamKit App Service
//  enabled for the app's identifier in the Apple Developer account.
//

import AVFoundation
import ShazamKit
import os

nonisolated struct ShazamSongRecognizer: SongRecognizing {
    /// Length of each excerpt; Shazam recommends a few seconds up to about 12.
    private static let excerptLength: TimeInterval = 10
    /// Where the excerpts are taken, as a fraction of the song: past the intro, then later on.
    private static let excerptPositions: [Double] = [0.3, 0.6]
    /// Offsets within `±1.5 s` are normal encoding padding; wider than `±8 s` is a different edit
    /// or a repeated chorus rather than an extra MV/vinyl intro.
    private static let minimumTimelineOffset: TimeInterval = 1.5
    private static let maximumTimelineOffset: TimeInterval = 8.0
    /// Two excerpts at different points of the song must agree within this much to confirm a
    /// constant intro offset (rules out matching Chorus 2 to Chorus 1).
    private static let offsetAgreementTolerance: TimeInterval = 0.5
    /// The lyrics search waits for the name, so a slow or missing network must not hold it up long.
    private static let timeout: Duration = .seconds(12)
    /// The Shazam service sometimes refuses a request (401, "enable the ShazamKit App Service")
    /// and accepts a later one: retried after these pauses (within `timeout`).
    private static let retryDelays: [Duration] = [.seconds(1), .seconds(2)]
    private static let sampleRate: Double = 44_100
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "finpro", category: "Recognition")

    func recognize(fileAt url: URL, duration: TimeInterval) async throws -> RecognizedSong? {
        try await withThrowingTaskGroup(of: RecognizedSong?.self) { group in
            group.addTask { try await Self.match(url, duration: duration) }
            group.addTask {
                try await Task.sleep(for: Self.timeout)
                Self.log.notice("recognition timed out")
                throw SongRecognitionError.unavailable
            }
            defer { group.cancelAll() }
            return try await group.next() ?? nil
        }
    }

    private static func match(_ url: URL, duration: TimeInterval) async throws -> RecognizedSong? {
        for (index, position) in excerptPositions.enumerated() {
            try Task.checkCancellation()
            guard let first = try await matchExcerpt(url, duration: duration, position: position) else { continue }
            var verifiedOffset: TimeInterval?
            if abs(first.offset) > minimumTimelineOffset && abs(first.offset) <= maximumTimelineOffset,
               index + 1 < excerptPositions.count,
               let second = try? await matchExcerpt(url, duration: duration, position: excerptPositions[index + 1]),
               abs(first.offset - second.offset) <= offsetAgreementTolerance {
                verifiedOffset = (first.offset + second.offset) / 2
            }
            let offsetNote = verifiedOffset.map { String(format: ", verified offset %+.2f s", $0) } ?? ""
            log.notice("recognized \(url.lastPathComponent, privacy: .public) as \(first.artist ?? "?", privacy: .public) - \(first.title, privacy: .public) (raw offset \(first.offset, format: .fixed(precision: 2)) s\(offsetNote, privacy: .public))")
            return RecognizedSong(title: first.title, artist: first.artist, timelineOffset: verifiedOffset)
        }
        log.notice("no match for \(url.lastPathComponent, privacy: .public)")
        return nil
    }

    private static func matchExcerpt(_ url: URL, duration: TimeInterval,
                                     position: Double) async throws -> (title: String, artist: String?, offset: TimeInterval)? {
        let start = max(0, min(duration - excerptLength, duration * position))
        let signature: SHSignature
        do { signature = try self.signature(of: url, from: start) } catch {
            log.error("signature failed: \(String(describing: error), privacy: .public)")
            throw SongRecognitionError.unavailable
        }
        var result = await SHSession().result(from: signature)
        for delay in retryDelays {
            guard case .error(let error, _) = result else { break }
            log.notice("recognition failed, retrying: \((error as NSError).domain, privacy: .public) \((error as NSError).code, privacy: .public)")
            try await Task.sleep(for: delay)
            result = await SHSession().result(from: signature)
        }
        switch result {
        case .match(let match):
            guard let item = match.mediaItems.first,
                  let title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
            let artist = item.artist?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (title, artist?.isEmpty == false ? artist : nil, start - item.matchOffset)
        case .noMatch:
            return nil
        case .error(let error, _):
            // Not reachable or not allowed (e.g. the ShazamKit App Service is off for this app):
            // the second excerpt would fail the same way, so stop. It may work another time.
            log.error("recognition failed: \(String(describing: error), privacy: .public)")
            throw SongRecognitionError.unavailable
        @unknown default:
            throw SongRecognitionError.unavailable
        }
    }

    /// A signature of `excerptLength` seconds from `start`, as mono 44.1 kHz PCM.
    private static func signature(of url: URL, from start: TimeInterval) throws -> SHSignature {
        let file = try AVAudioFile(forReading: url)
        let input = file.processingFormat
        file.framePosition = min(file.length, AVAudioFramePosition(start * input.sampleRate))
        let frames = AVAudioFrameCount(max(0, min(Double(file.length - file.framePosition), excerptLength * input.sampleRate)))
        guard frames > 0, let excerpt = AVAudioPCMBuffer(pcmFormat: input, frameCapacity: frames),
              let output = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let converter = AVAudioConverter(from: input, to: output),
              let converted = AVAudioPCMBuffer(pcmFormat: output, frameCapacity:
                AVAudioFrameCount(Double(frames) * sampleRate / input.sampleRate) + 4096)
        else { throw SongRecognitionError.unavailable }
        try file.read(into: excerpt, frameCount: frames)
        var delivered = false
        var conversionError: NSError?
        converter.convert(to: converted, error: &conversionError) { _, status in
            if delivered { status.pointee = .endOfStream; return nil }
            delivered = true
            status.pointee = .haveData
            return excerpt
        }
        if let conversionError { throw conversionError }
        let generator = SHSignatureGenerator()
        try generator.append(converted, at: nil)
        return generator.signature()
    }
}
