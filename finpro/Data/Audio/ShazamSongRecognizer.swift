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
    /// The lyrics search waits for the name, so a slow or missing network must not hold it up long.
    private static let timeout: Duration = .seconds(6)
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
        var failed = false
        for position in excerptPositions {
            try Task.checkCancellation()
            let start = max(0, min(duration - excerptLength, duration * position))
            let signature: SHSignature
            do { signature = try self.signature(of: url, from: start) } catch {
                log.error("signature failed: \(String(describing: error), privacy: .public)")
                throw SongRecognitionError.unavailable
            }
            switch await SHSession().result(from: signature) {
            case .match(let match):
                guard let item = match.mediaItems.first,
                      let title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { continue }
                let artist = item.artist?.trimmingCharacters(in: .whitespacesAndNewlines)
                log.notice("recognized \(url.lastPathComponent, privacy: .public) as \(artist ?? "?", privacy: .public) - \(title, privacy: .public)")
                return RecognizedSong(title: title, artist: artist?.isEmpty == false ? artist : nil)
            case .noMatch:
                continue
            case .error(let error, _):
                log.error("recognition failed: \(String(describing: error), privacy: .public)")
                failed = true
            @unknown default:
                failed = true
            }
        }
        log.notice("no match for \(url.lastPathComponent, privacy: .public)\(failed ? " (errors)" : "", privacy: .public)")
        // An error (not a plain no-match) means it may work another time.
        if failed { throw SongRecognitionError.unavailable }
        return nil
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
