//
//  LyricsAudioMatcher.swift
//  finpro
//
//  Picks the best-aligned LRCLIB candidate when multiple distinct synced-lyrics timelines exist
//  within duration tolerance (e.g. a 271 s radio-edit LRC uploaded onto a 321 s album track).
//  Computes a fast 4 Hz vocal-band center-prominence curve from the local audio file and compares
//  each candidate's sung-line mask against it.
//

import AVFoundation
import Foundation
import os

nonisolated enum LyricsAudioMatcher {
    /// Analysis sample rate (8 kHz covers the 300–3400 Hz vocal band with minimal decode cost).
    private static let sampleRate: Double = 8_000
    /// Activity bins per second (4 Hz = 250 ms resolution).
    private static let binsPerSecond: Double = 4
    /// Minimum difference (seconds) between two candidate timelines before running audio analysis.
    private static let distinctTimelineTolerance: TimeInterval = 2.0
    /// Minimum Pearson correlation required to trust acoustic scoring over closest duration.
    private static let minimumConfidentCorrelation: Double = 0.15
    /// Minimum correlation improvement over the closest-duration candidate to override it.
    private static let minimumOverrideMargin: Double = 0.03
    /// Quiet-frame gate (dBFS) so near-silent intros/outros don't skew center-vs-side ratios.
    private static let activeGateDBFS: Double = -45
    /// Stereo detection threshold (mean side energy in dBFS).
    private static let stereoSideThresholdDBFS: Double = -70
    /// First-order high-pass coefficient (~300 Hz at 8 kHz) to isolate the vocal band from bass/kick.
    private static let highPassAlpha: Float = 0.80
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "finpro", category: "Lyrics")

    /// Chooses the acoustically best-aligned record among `candidates` (already filtered to healthy
    /// synced records within `durationTolerance`). Falls back to the closest-duration record when
    /// all candidates share one timeline or the audio lacks clear vocal/instrumental contrast.
    static func bestRecord(
        among candidates: [LRCLibLyricsProvider.Record],
        duration: TimeInterval,
        audioURL: URL
    ) async -> LRCLibLyricsProvider.Record? {
        guard !candidates.isEmpty else { return nil }
        let baseline = candidates.min { abs($0.duration - duration) < abs($1.duration - duration) }!
        guard candidates.count > 1 else { return baseline }

        let groups = distinctTimelineGroups(candidates, duration: duration)
        guard groups.count > 1 else { return baseline }

        guard let curve = await vocalActivityCurve(audioURL: audioURL), !curve.isEmpty else {
            return baseline
        }

        let baselineLines = LRCLyricsParser.lines(from: baseline.syncedLyrics ?? "", duration: duration)
        let baselineScore = correlation(lines: baselineLines, curve: curve)
        var bestRecord = baseline
        var bestScore = baselineScore

        for group in groups {
            let score = correlation(lines: group.lines, curve: curve)
            if score > bestScore {
                bestScore = score
                bestRecord = group.closest
            }
        }

        if bestRecord != baseline,
           bestScore >= minimumConfidentCorrelation,
           bestScore - baselineScore >= minimumOverrideMargin {
            log.notice("acoustic lyrics match overrode duration pick: corr \(bestScore, format: .fixed(precision: 3)) vs \(baselineScore, format: .fixed(precision: 3)) (dur \(bestRecord.duration, format: .fixed(precision: 1)) s vs \(baseline.duration, format: .fixed(precision: 1)) s)")
            return bestRecord
        }
        return baseline
    }

    /// Groups candidates whose first, middle, and last line timestamps agree within `distinctTimelineTolerance`.
    private static func distinctTimelineGroups(
        _ candidates: [LRCLibLyricsProvider.Record],
        duration: TimeInterval
    ) -> [(closest: LRCLibLyricsProvider.Record, lines: [LyricLine])] {
        var groups: [(anchor: (Double, Double, Double), closest: LRCLibLyricsProvider.Record, lines: [LyricLine])] = []
        for record in candidates {
            let lines = LRCLyricsParser.lines(from: record.syncedLyrics ?? "", duration: duration)
            guard let first = lines.first, let last = lines.last else { continue }
            let mid = lines[lines.count / 2]
            let key = (first.start, mid.start, last.start)
            if let index = groups.firstIndex(where: {
                abs($0.anchor.0 - key.0) < distinctTimelineTolerance
                    && abs($0.anchor.1 - key.1) < distinctTimelineTolerance
                    && abs($0.anchor.2 - key.2) < distinctTimelineTolerance
            }) {
                if abs(record.duration - duration) < abs(groups[index].closest.duration - duration) {
                    groups[index].closest = record
                    groups[index].lines = lines
                }
            } else {
                groups.append((key, record, lines))
            }
        }
        return groups.map { ($0.closest, $0.lines) }
    }

    /// Pearson correlation between the candidate's sung-word mask and the z-scored vocal activity curve.
    static func correlation(lines: [LyricLine], curve: [Double]) -> Double {
        guard !curve.isEmpty, !lines.isEmpty else { return -.infinity }
        var mask = [Double](repeating: 0, count: curve.count)
        for line in lines {
            let sungEnd = min(line.end, line.words.last?.end ?? line.end)
            let startBin = max(0, Int(line.start * binsPerSecond))
            let endBin = min(curve.count, Int(sungEnd * binsPerSecond))
            if startBin < endBin {
                for bin in startBin..<endBin { mask[bin] = 1 }
            }
        }
        let count = Double(curve.count)
        let meanMask = mask.reduce(0, +) / count
        var numerator = 0.0
        var denomMask = 0.0
        var denomCurve = 0.0
        for i in 0..<curve.count {
            let dm = mask[i] - meanMask
            let dc = curve[i]
            numerator += dm * dc
            denomMask += dm * dm
            denomCurve += dc * dc
        }
        guard denomMask > 1e-6, denomCurve > 1e-6 else { return 0 }
        return numerator / sqrt(denomMask * denomCurve)
    }

    /// Reads `audioURL` at 8 kHz stereo and computes a z-scored 4 Hz vocal-prominence curve.
    private static func vocalActivityCurve(audioURL: URL) async -> [Double]? {
        let asset = AVURLAsset(url: audioURL)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first else { return nil }
        return await Task.detached(priority: .userInitiated) {
            Self.readVocalActivity(asset: asset, track: track)
        }.value
    }

    private static func readVocalActivity(asset: AVAsset, track: AVAssetTrack) -> [Double]? {
        guard let reader = try? AVAssetReader(asset: asset) else { return nil }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
        ])
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }

        let hop = Int(sampleRate / binsPerSecond)
        var midHP: [Double] = []
        var sideHP: [Double] = []
        var midFull: [Double] = []

        var prevMid: Float = 0
        var prevSide: Float = 0
        var hpMid: Float = 0
        var hpSide: Float = 0
        var energyMidHP = 0.0
        var energySideHP = 0.0
        var energyMidFull = 0.0
        var binSamples = 0
        let invHop = 1.0 / Double(hop)

        while let sampleBuffer = output.copyNextSampleBuffer(),
              let block = CMSampleBufferGetDataBuffer(sampleBuffer) {
            if Task.isCancelled {
                reader.cancelReading()
                return nil
            }
            let length = CMBlockBufferGetDataLength(block)
            let floatCount = length / MemoryLayout<Float>.size
            guard floatCount >= 2 else { continue }
            var interleaved = [Float](repeating: 0, count: floatCount)
            interleaved.withUnsafeMutableBytes {
                _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!)
            }
            let frameCount = floatCount / 2
            for frame in 0..<frameCount {
                let left = interleaved[2 * frame]
                let right = interleaved[2 * frame + 1]
                let mid = 0.5 * (left + right)
                let side = 0.5 * (left - right)
                hpMid = highPassAlpha * (hpMid + mid - prevMid)
                prevMid = mid
                hpSide = highPassAlpha * (hpSide + side - prevSide)
                prevSide = side
                energyMidHP += Double(hpMid * hpMid)
                energySideHP += Double(hpSide * hpSide)
                energyMidFull += Double(mid * mid)
                binSamples += 1
                if binSamples == hop {
                    midHP.append(10 * log10(energyMidHP * invHop + 1e-10))
                    sideHP.append(10 * log10(energySideHP * invHop + 1e-10))
                    midFull.append(10 * log10(energyMidFull * invHop + 1e-10))
                    energyMidHP = 0
                    energySideHP = 0
                    energyMidFull = 0
                    binSamples = 0
                }
            }
        }
        guard reader.status == .completed, !midHP.isEmpty else { return nil }

        let binCount = midHP.count
        let meanSide = sideHP.reduce(0, +) / Double(binCount)
        let isStereo = meanSide > stereoSideThresholdDBFS

        var curve = [Double](repeating: 0, count: binCount)
        for i in 0..<binCount {
            let vocalBandRatio = midHP[i] - midFull[i]
            let centerRatio = isStereo ? (midHP[i] - sideHP[i]) : 0.0
            let gate = midFull[i] > activeGateDBFS ? 1.0 : 0.0
            curve[i] = gate * (0.65 * centerRatio + 0.35 * vocalBandRatio)
        }
        let mean = curve.reduce(0, +) / Double(binCount)
        let variance = curve.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(binCount)
        let std = max(1e-6, sqrt(variance))
        return curve.map { ($0 - mean) / std }
    }
}
