//
//  CrepeAnalysisRepository.swift
//  finpro
//
//  Guide extraction fallback (PRD §5.3): reads the trimmed vocal guide, runs CREPE every
//  50 ms and reduces the pitch track to notes with ExtractGuideNotesUseCase.
//

import Accelerate
import AVFoundation
import Foundation
import os

nonisolated struct CrepeAnalysisRepository: AudioAnalysisRepository {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "finpro", category: "Analysis")
    /// Analysis window: 4096 samples at 48 kHz (~85 ms), the same as the live path.
    static let windowDuration: TimeInterval = 4096.0 / 48_000

    /// Frames quieter than this fraction of the track's loud level (90th percentile RMS, about -12 dB)
    /// are treated as unvoiced, so a quiet bass or bleed under the gaps is not mistaken for the melody.
    static let relativeLevelGate = 0.25
    static let loudLevelPercentile = 0.9

    private let modelURL: URL?
    private let hop: TimeInterval

    /// `modelURL` nil = `CrepeTiny.mlmodelc` from the app bundle.
    init(modelURL: URL? = nil, hop: TimeInterval = AppConfiguration.default.pitchHop) {
        self.modelURL = modelURL
        self.hop = hop
    }

    func extractVocalGuideNotes(from vocalGuideURL: URL) async throws -> [TargetMIDINote] {
        let modelURL = modelURL
        let hop = hop
        return try await Task.detached(priority: .userInitiated) {
            try Self.extract(from: vocalGuideURL, modelURL: modelURL, hop: hop)
        }.value
    }

    private static func extract(from url: URL, modelURL: URL?, hop: TimeInterval) throws -> [TargetMIDINote] {
        let clock = ContinuousClock()
        let started = clock.now
        let detector: CrepePitchDetector
        do {
            detector = try CrepePitchDetector(modelURL: modelURL)
        } catch {
            throw NSError(
                domain: "CrepeAnalysis", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "CREPE model could not be loaded: \(error.localizedDescription)"])
        }
        let loadSeconds = (clock.now - started) / .seconds(1)
        let readStarted = clock.now
        let (samples, rate) = try readMono(url)
        let readSeconds = (clock.now - readStarted) / .seconds(1)
        guard rate > 0 else { return [] }
        let window = Int((rate * windowDuration).rounded(.up))
        guard samples.count >= window else { return [] }

        let inferStarted = clock.now
        let estimates = try detector.analyzeTrack(samples, sampleRate: rate, hop: hop, windowDuration: windowDuration)
        let inferSeconds = (clock.now - inferStarted) / .seconds(1)
        let levels = estimates.map(\.estimate.rms).sorted()
        let loud = levels.isEmpty ? 0 : levels[min(levels.count - 1, Int(Double(levels.count) * loudLevelPercentile))]
        let frames = estimates.map { time, estimate -> GuidePitchFrame in
            let audible = estimate.rms >= loud * relativeLevelGate
            let midi = audible ? estimate.frequency.flatMap(PitchMath.midi(fromFrequency:)).map(Float.init) : nil
            return GuidePitchFrame(time: time, midi: midi, confidence: estimate.confidence)
        }
        let notes = ExtractGuideNotesUseCase(hop: hop).execute(frames: frames)
        let totalSeconds = (clock.now - started) / .seconds(1)
        let audioSeconds = Double(samples.count) / rate
        log.notice("""
            crepe timing: \(audioSeconds, format: .fixed(precision: 1)) s audio, \(estimates.count, privacy: .public) frames, \(notes.count, privacy: .public) notes in \(totalSeconds, format: .fixed(precision: 2)) s \
            (model \(loadSeconds, format: .fixed(precision: 2)) s, read \(readSeconds, format: .fixed(precision: 2)) s, infer \(inferSeconds, format: .fixed(precision: 2)) s)
            """)
        return notes
    }

    /// Whole file as mono float (channels averaged).
    private static func readMono(_ url: URL) throws -> (samples: [Float], rate: Double) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let chunkSize: AVAudioFrameCount = 65_536
        guard file.length > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkSize) else {
            return ([], format.sampleRate)
        }
        // AVAudioFile may return fewer frames than asked in one read (seen with mono WAV),
        // so read until the end instead of trusting a single call.
        let channelCount = Int(format.channelCount)
        var scale = 1 / Float(channelCount)
        var mono: [Float] = []
        mono.reserveCapacity(Int(file.length))
        var scratch = channelCount > 1 ? [Float](repeating: 0, count: Int(chunkSize)) : []
        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: chunkSize)
            guard buffer.frameLength > 0, let channels = buffer.floatChannelData else { break }
            let count = Int(buffer.frameLength)
            if channelCount == 1 {
                mono.append(contentsOf: UnsafeBufferPointer(start: channels[0], count: count))
            } else {
                scratch.withUnsafeMutableBufferPointer { dst in
                    dst.baseAddress!.update(from: channels[0], count: count)
                    for channel in 1..<channelCount {
                        vDSP_vadd(dst.baseAddress!, 1, channels[channel], 1, dst.baseAddress!, 1, vDSP_Length(count))
                    }
                    vDSP_vsmul(dst.baseAddress!, 1, &scale, dst.baseAddress!, 1, vDSP_Length(count))
                }
                mono.append(contentsOf: scratch.prefix(count))
            }
        }
        return (mono, format.sampleRate)
    }
}
