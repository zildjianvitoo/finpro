//
//  HTDemucsStemSeparationRepository.swift
//  finpro
//
//  On-device vocal separation with htdemucs (Demucs v4, Meta, MIT) converted to CoreML: only the
//  network is in the model; the demucs STFT/iSTFT and the 7.8 s chunking (12.5 % overlap,
//  triangular weights, fixed song-timeline grid with per-chunk disk cache) run here.
//  Vocal stem = mono "vocals" source; instrumental = drums + bass + other.
//  Spike, numbers and conversion: docs/test-reports/htdemucs-coreml-spike-2026-11-03.md.
//

import Accelerate
import AVFoundation
import CoreML
import os

nonisolated final class HTDemucsStemSeparationRepository: StemSeparationRepository, LeadInStemSeparation, StemPreseparation, @unchecked Sendable {
    /// The model was trained at 44.1 kHz.
    static let sampleRate = 44_100.0
    /// The model's fixed window: htdemucs' training segment, 39/5 s at 44.1 kHz.
    static let segmentSamples = 343_980
    /// 12.5 % overlap (~0.975 s triangular crossfade) on a fixed song-timeline grid so adjacent
    /// trims and background pre-separation reuse the exact same cached chunks.
    static let chunkStride = segmentSamples * 7 / 8
    /// Demucs drops 2 STFT frames at each chunk edge (~4096 samples); keeping every requested
    /// boundary at least this far inside a chunk avoids edge artifacts.
    private static let edgeMargin = 4 * DemucsSpectrogram.hop
    /// Maximum number of song chunk folders retained in Caches (LRU pruned).
    private static let maxCachedSongChunkFolders = 3
    /// Sources in model output order.
    static let sources = ["drums", "bass", "other", "vocals"]
    static let vocalsSource = 3

    /// Where the preparation time goes (model load, audio I/O, STFT, inference, iSTFT); a few
    /// lines per song, also in Release builds, for device tests.
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "finpro", category: "Separation")

    private let modelURL: URL?
    private let directory: URL
    private let lock = NSLock()
    private var model: MLModel?
    private let coordinator = ChunkCoordinator()

    init(modelURL: URL? = nil,
         directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
             .appendingPathComponent("HTDemucsSeparation", isDirectory: true)) {
        self.modelURL = modelURL
        self.directory = directory
    }

    // MARK: - StemSeparationRepository & LeadInStemSeparation

    func separateStems(from audioURL: URL, trimRange: ClosedRange<TimeInterval>) async throws -> SeparatedStems {
        try await separateStems(from: audioURL, trimRange: trimRange, leadInDuration: 0).stems
    }

    func separateStems(from audioURL: URL, trimRange: ClosedRange<TimeInterval>,
                       leadInDuration: TimeInterval) async throws -> (stems: SeparatedStems, leadIn: SeparatedStems?) {
        let asset = AVURLAsset(url: audioURL)
        if (try? await asset.load(.hasProtectedContent)) == true { throw CoreMLSeparationError.drmProtected }
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let duration = try? await asset.load(.duration).seconds else { throw CoreMLSeparationError.unreadable }
        guard trimRange.lowerBound >= 0, trimRange.upperBound <= duration + 0.01, trimRange.upperBound > trimRange.lowerBound else {
            throw CoreMLSeparationError.invalidTrim
        }
        let mainFolder = directory.appendingPathComponent(Self.cacheKey(audioURL, trimRange), isDirectory: true)
        let mainStems = Self.stems(in: mainFolder)
        let mainCached = Self.isCached(mainStems)

        let effectiveLeadIn = leadInDuration > 0 ? min(leadInDuration, trimRange.lowerBound) : 0
        let leadRange: ClosedRange<TimeInterval>? = effectiveLeadIn > 0
            ? (trimRange.lowerBound - effectiveLeadIn)...trimRange.lowerBound : nil
        let leadFolder = leadRange.map { directory.appendingPathComponent(Self.cacheKey(audioURL, $0), isDirectory: true) }
        let leadStems = leadFolder.map(Self.stems(in:))
        let leadCached = leadStems.map(Self.isCached) ?? true

        if mainCached && leadCached {
            Self.log.notice("htdemucs: cache hit for \(trimRange.upperBound - trimRange.lowerBound + effectiveLeadIn, format: .fixed(precision: 1)) s")
            return (mainStems, leadStems)
        }

        // If the main part is already cached and only the lead-in is missing, separate just the lead-in.
        let fullRange: ClosedRange<TimeInterval>
        let splitLeadIn: Bool
        if mainCached, let leadRange {
            fullRange = leadRange
            splitLeadIn = false
        } else if let leadRange {
            fullRange = leadRange.lowerBound...trimRange.upperBound
            splitLeadIn = true
        } else {
            fullRange = trimRange
            splitLeadIn = false
        }

        let clock = ContinuousClock()
        let loadStarted = clock.now
        let model = try loadModel()
        let loadSeconds = (clock.now - loadStarted) / .seconds(1)

        let decodeStarted = clock.now
        let songKey = Self.songCacheKey(audioURL)
        let songFolder = chunksRoot.appendingPathComponent(songKey, isDirectory: true)
        let source = try await coordinator.ensureDecodedSource(songKey: songKey, songFolder: songFolder,
                                                               asset: asset, track: track, chunksRoot: chunksRoot)
        let decodeSeconds = (clock.now - decodeStarted) / .seconds(1)

        let mainSamples = Int(((trimRange.upperBound - trimRange.lowerBound) * Self.sampleRate).rounded())
        let leadSamples = Int((effectiveLeadIn * Self.sampleRate).rounded())
        let fullStart = min(source.samples, max(0, Int((fullRange.lowerBound * Self.sampleRate).rounded())))
        let fullExpected = splitLeadIn ? (leadSamples + mainSamples) : Int(((fullRange.upperBound - fullRange.lowerBound) * Self.sampleRate).rounded())
        let fullEnd = min(source.samples, fullStart + fullExpected)
        let range = Self.chunkRange(start: fullStart, end: fullEnd, songSamples: source.samples)

        var cachedCount = 0
        var computedCount = 0
        var inputTime = Duration.zero, modelTime = Duration.zero, outputTime = Duration.zero

        for k in range {
            try Task.checkCancellation()
            let chunkURL = songFolder.appendingPathComponent("\(k).bin")
            if Self.isChunkValid(chunkURL) {
                cachedCount += 1
                continue
            }
            let stats = try await coordinator.computeChunkIfNeeded(
                key: ChunkCoordinator.ChunkID(songKey: songKey, index: k),
                priority: .userInitiated
            ) {
                try Self.computeAndStoreChunk(index: k, sourceURL: source.url, songSamples: source.samples,
                                              destination: chunkURL, model: model)
            }
            if let stats {
                computedCount += 1
                inputTime += stats.inputTime
                modelTime += stats.modelTime
                outputTime += stats.outputTime
            } else {
                cachedCount += 1
            }
        }

        let assembleStarted = clock.now
        try await Task.detached(priority: .userInitiated) {
            let fullMix = try Self.readPCM(from: source.url, start: fullStart, count: fullExpected)
            let (vocalsMono, instrumental) = try Self.assemble(
                chunkRange: range, songFolder: songFolder, songSamples: source.samples,
                fullStart: fullStart, fullCount: fullExpected)
            let writeStarted = clock.now
            if splitLeadIn, let leadFolder, let leadStems {
                let leadEnd = min(leadSamples, fullMix[0].count)
                let mainEnd = min(leadEnd + mainSamples, fullMix[0].count)
                if !leadCached {
                    try Self.writeStems(
                        mix: [Array(fullMix[0][0..<leadEnd]), Array(fullMix[1][0..<leadEnd])],
                        vocalsMono: Array(vocalsMono[0..<leadEnd]),
                        instrumental: [Array(instrumental[0][0..<leadEnd]), Array(instrumental[1][0..<leadEnd])],
                        to: leadFolder, stems: leadStems)
                }
                try Self.writeStems(
                    mix: [Array(fullMix[0][leadEnd..<mainEnd]), Array(fullMix[1][leadEnd..<mainEnd])],
                    vocalsMono: Array(vocalsMono[leadEnd..<mainEnd]),
                    instrumental: [Array(instrumental[0][leadEnd..<mainEnd]), Array(instrumental[1][leadEnd..<mainEnd])],
                    to: mainFolder, stems: mainStems)
            } else if mainCached, let leadFolder, let leadStems {
                try Self.writeStems(mix: fullMix, vocalsMono: vocalsMono, instrumental: instrumental, to: leadFolder, stems: leadStems)
            } else {
                try Self.writeStems(mix: fullMix, vocalsMono: vocalsMono, instrumental: instrumental, to: mainFolder, stems: mainStems)
            }
            let assembleSeconds = (writeStarted - assembleStarted) / .seconds(1)
            let writeSeconds = (clock.now - writeStarted) / .seconds(1)
            Self.log.notice("""
                htdemucs timing: \(computedCount) computed + \(cachedCount) cached (\(range.count) total), \
                STFT + inputs \(inputTime / .seconds(1), format: .fixed(precision: 2)) s, \
                model \(modelTime / .seconds(1), format: .fixed(precision: 2)) s, \
                iSTFT + mixing \(outputTime / .seconds(1), format: .fixed(precision: 2)) s
                """)
            Self.log.notice("""
                htdemucs timing: model load \(loadSeconds, format: .fixed(precision: 2)) s, decode \(decodeSeconds, format: .fixed(precision: 2)) s, \
                assemble \(assembleSeconds, format: .fixed(precision: 2)) s, write stems \(writeSeconds, format: .fixed(precision: 2)) s
                """)
        }.value
        return (mainStems, leadStems)
    }

    // MARK: - StemPreseparation

    /// Warms chunk cache entries for `trimRange` (plus `leadInDuration`) at low priority while the
    /// user is on the trim screen. Stops cleanly on cancellation (e.g. backgrounding or Prepare tap).
    func preseparate(audioURL: URL, trimRange: ClosedRange<TimeInterval>, leadInDuration: TimeInterval) async {
        do {
            try Task.checkCancellation()
            let asset = AVURLAsset(url: audioURL)
            if (try? await asset.load(.hasProtectedContent)) == true { return }
            guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
                  let duration = try? await asset.load(.duration).seconds,
                  trimRange.lowerBound >= 0, trimRange.upperBound <= duration + 0.01,
                  trimRange.upperBound > trimRange.lowerBound else { return }
            let model = try loadModel()
            try Task.checkCancellation()

            let songKey = Self.songCacheKey(audioURL)
            let songFolder = chunksRoot.appendingPathComponent(songKey, isDirectory: true)
            let source = try await coordinator.ensureDecodedSource(songKey: songKey, songFolder: songFolder,
                                                                   asset: asset, track: track, chunksRoot: chunksRoot)
            try Task.checkCancellation()

            let effectiveLeadIn = leadInDuration > 0 ? min(leadInDuration, trimRange.lowerBound) : 0
            let fullStart = min(source.samples, max(0, Int(((trimRange.lowerBound - effectiveLeadIn) * Self.sampleRate).rounded())))
            let fullEnd = min(source.samples, max(fullStart + 1, Int((trimRange.upperBound * Self.sampleRate).rounded())))
            let range = Self.chunkRange(start: fullStart, end: fullEnd, songSamples: source.samples)

            var warmed = 0
            var alreadyCached = 0
            let started = ContinuousClock.now
            for k in range {
                if Task.isCancelled { break }
                let chunkURL = songFolder.appendingPathComponent("\(k).bin")
                if Self.isChunkValid(chunkURL) {
                    alreadyCached += 1
                    continue
                }
                let stats = try await coordinator.computeChunkIfNeeded(
                    key: ChunkCoordinator.ChunkID(songKey: songKey, index: k),
                    priority: .utility
                ) {
                    try Self.computeAndStoreChunk(index: k, sourceURL: source.url, songSamples: source.samples,
                                                  destination: chunkURL, model: model)
                }
                if stats != nil { warmed += 1 } else { alreadyCached += 1 }
            }
            if warmed > 0 {
                let elapsed = (ContinuousClock.now - started) / .seconds(1)
                let suffix = Task.isCancelled ? " (paused)" : ""
                Self.log.notice("htdemucs preseparate: +\(warmed) chunks (\(alreadyCached) cached, target \(range.count)) in \(elapsed, format: .fixed(precision: 2)) s\(suffix, privacy: .public)")
            }
        } catch is CancellationError {
            // Normal: user moved the trimmer, backgrounded the app, or tapped Prepare.
        } catch {
            Self.log.notice("htdemucs preseparate stopped: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Model

    /// Loads the model and separates one silent window, so the first song doesn't wait for the
    /// model load and the GPU set-up (ModelPrewarmer, at app start).
    func prewarm() throws {
        let model = try loadModel()
        // Shorter than one chunk stride, so it is a single model call.
        let silence = [Float](repeating: 0, count: Self.segmentSamples / 2)
        _ = try Self.separate([silence, silence], model: model)
    }

    private func loadModel() throws -> MLModel {
        try lock.withLock {
            if let model { return model }
            guard let url = modelURL ?? Bundle.main.url(forResource: "HTDemucs", withExtension: "mlmodelc") else {
                throw CoreMLSeparationError.modelUnavailable
            }
            let configuration = MLModelConfiguration()
            // GPU: on the Neural Engine the model's float32 normalisation ops split it into CPU/ANE
            // pieces (18× slower, ~8 GB), and `.all` gives wrong output (spike §4). Where Core ML
            // runs it on the CPU instead (Simulator, possibly the background) the stems get noisier
            // (~30 dB SNR vs ~60 dB on the GPU) but stay usable.
            configuration.computeUnits = .cpuAndGPU
            let loaded = try MLModel(contentsOf: url, configuration: configuration)
            model = loaded
            return loaded
        }
    }

    // MARK: - Separation (single-chunk & in-memory)

    private struct ChunkStats: Sendable {
        let inputTime: Duration
        let modelTime: Duration
        let outputTime: Duration
    }

    /// Runs HTDemucs on one fixed `segmentSamples` stereo window, returning mono vocals and stereo
    /// instrumental of length `segmentSamples`.
    private static func separateWindow(_ window: [[Float]], model: MLModel) throws -> (vocals: [Float], instL: [Float], instR: [Float], stats: ChunkStats) {
        let spectrogram = DemucsSpectrogram()
        let segment = segmentSamples
        let frames = spectrogram.frameCount(sampleCount: segment)
        let bins = DemucsSpectrogram.bins
        let instrumentalSources = (0..<sources.count).filter { $0 != vocalsSource }

        let mixInput = try MLMultiArray(shape: [1, 2, NSNumber(value: segment)], dataType: .float32)
        let specInput = try MLMultiArray(shape: [1, 4, NSNumber(value: bins), NSNumber(value: frames)], dataType: .float32)
        let mixStrides = mixInput.strides.map(\.intValue)
        let specStrides = specInput.strides.map(\.intValue)
        let clock = ContinuousClock()

        return try autoreleasepool {
            let inputStarted = clock.now
            let mixPointer = mixInput.dataPointer.bindMemory(to: Float.self, capacity: mixInput.count)
            let specPointer = specInput.dataPointer.bindMemory(to: Float.self, capacity: specInput.count)
            for c in 0..<2 {
                copy(window[c], to: mixPointer + c * mixStrides[1], stride: mixStrides[2])
                // Complex as channels: [L real, L imaginary, R real, R imaginary], each (bin, frame).
                let spectra = spectrogram.forward(window[c])
                writePlane(frameMajor(spectra.map(\.real), bins: bins), to: specPointer + (2 * c) * specStrides[1],
                           binStride: specStrides[2], frameStride: specStrides[3], bins: bins, frames: frames)
                writePlane(frameMajor(spectra.map(\.imaginary), bins: bins), to: specPointer + (2 * c + 1) * specStrides[1],
                           binStride: specStrides[2], frameStride: specStrides[3], bins: bins, frames: frames)
            }

            let modelStarted = clock.now
            let prediction = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["mix": mixInput, "spec": specInput]))
            let outputStarted = clock.now
            guard let specOut = prediction.featureValue(for: "spec_out")?.multiArrayValue,
                  let waveOut = prediction.featureValue(for: "wave_out")?.multiArrayValue,
                  specOut.dataType == .float32, waveOut.dataType == .float32 else {
                throw CoreMLSeparationError.modelUnavailable
            }
            let so = specOut.strides.map(\.intValue)
            let wo = waveOut.strides.map(\.intValue)
            let specValues = UnsafePointer(specOut.dataPointer.bindMemory(to: Float.self, capacity: specOut.count))
            let waveValues = UnsafePointer(waveOut.dataPointer.bindMemory(to: Float.self, capacity: waveOut.count))

            // Vocals: average L + R in the linear spectrum and time branch so only one iSTFT runs.
            func monoVocalSpec(_ part: Int) -> [Float] {
                let left = readPlane(specValues + (vocalsSource * 4 + part) * so[1], binStride: so[2], frameStride: so[3], bins: bins, frames: frames)
                let right = readPlane(specValues + (vocalsSource * 4 + 2 + part) * so[1], binStride: so[2], frameStride: so[3], bins: bins, frames: frames)
                return vDSP.multiply(0.5, vDSP.add(left, right))
            }
            let vocalReal = monoVocalSpec(0), vocalImag = monoVocalSpec(1)
            let vocalSpectra = (0..<frames).map { t in
                ShortTimeFourierTransform.Spectrum(real: Array(vocalReal[(t * bins)..<((t + 1) * bins)]) + [0],
                                                   imaginary: Array(vocalImag[(t * bins)..<((t + 1) * bins)]) + [0])
            }
            var vocalChunk = spectrogram.inverse(vocalSpectra, length: segment)
            var halfScalar: Float = 0.5
            vocalChunk.withUnsafeMutableBufferPointer { samples in
                for c in 0..<2 {
                    vDSP_vsma(waveValues + (vocalsSource * 2 + c) * wo[1], vDSP_Stride(wo[2]),
                              &halfScalar, samples.baseAddress!, 1, samples.baseAddress!, 1, vDSP_Length(segment))
                }
            }

            // Instrumental: stereo drums + bass + other (one iSTFT per channel).
            var inst: [[Float]] = []
            inst.reserveCapacity(2)
            for c in 0..<2 {
                func summed(_ part: Int) -> [Float] {
                    instrumentalSources.map { s in
                        readPlane(specValues + (s * 4 + 2 * c + part) * so[1], binStride: so[2], frameStride: so[3],
                                  bins: bins, frames: frames)
                    }.reduce([Float](repeating: 0, count: bins * frames)) { vDSP.add($0, $1) }
                }
                let real = summed(0), imaginary = summed(1)
                let spectra = (0..<frames).map { t in
                    ShortTimeFourierTransform.Spectrum(real: Array(real[(t * bins)..<((t + 1) * bins)]) + [0],
                                                       imaginary: Array(imaginary[(t * bins)..<((t + 1) * bins)]) + [0])
                }
                var chunk = spectrogram.inverse(spectra, length: segment)
                chunk.withUnsafeMutableBufferPointer { samples in
                    for s in instrumentalSources {
                        vDSP_vadd(samples.baseAddress!, 1, waveValues + (s * 2 + c) * wo[1], vDSP_Stride(wo[2]),
                                  samples.baseAddress!, 1, vDSP_Length(segment))
                    }
                }
                inst.append(chunk)
            }
            let stats = ChunkStats(inputTime: modelStarted - inputStarted,
                                   modelTime: outputStarted - modelStarted,
                                   outputTime: clock.now - outputStarted)
            return (vocalChunk, inst[0], inst[1], stats)
        }
    }

    /// In-memory separation used by `prewarm()` and tests.
    static func separate(_ channels: [[Float]], model: MLModel) throws -> (vocals: [Float], instrumental: [[Float]]) {
        let length = channels[0].count
        let range = chunkRange(start: 0, end: length, songSamples: length)
        let weight = triangleWeight()

        var vocalsMono = [Float](repeating: 0, count: length)
        var instLOut = [Float](repeating: 0, count: length)
        var instROut = [Float](repeating: 0, count: length)
        var total = [Float](repeating: 0, count: length)
        var inputTime = Duration.zero, modelTime = Duration.zero, outputTime = Duration.zero

        for k in range {
            try Task.checkCancellation()
            let (window, offset, trim, count) = windowSlice(channels: channels, chunkIndex: k, songSamples: length)
            let (v, iL, iR, stats) = try separateWindow(window, model: model)
            inputTime += stats.inputTime
            modelTime += stats.modelTime
            outputTime += stats.outputTime
            accumulate(vocals: v, instL: iL, instR: iR, weight: weight,
                       srcOffset: trim, dstOffset: offset, count: count,
                       total: &total, vocalsMono: &vocalsMono, instLOut: &instLOut, instROut: &instROut)
        }
        log.notice("""
            htdemucs timing: \(range.count) chunks, STFT + inputs \(inputTime / .seconds(1), format: .fixed(precision: 2)) s, \
            model \(modelTime / .seconds(1), format: .fixed(precision: 2)) s, iSTFT + mixing \(outputTime / .seconds(1), format: .fixed(precision: 2)) s
            """)
        return (vDSP.divide(vocalsMono, total), [vDSP.divide(instLOut, total), vDSP.divide(instROut, total)])
    }

    // MARK: - Chunk grid & disk cache

    private var chunksRoot: URL {
        directory.appendingPathComponent("chunks", isDirectory: true)
    }

    private static var chunkByteCount: Int { 3 * segmentSamples * MemoryLayout<Float>.size }

    /// Fixed grid chunks covering `[start, end)` with at least `edgeMargin` of interior context
    /// on both sides (whenever the song extends that far).
    private static func chunkRange(start: Int, end: Int, songSamples: Int) -> ClosedRange<Int> {
        guard songSamples > segmentSamples else { return 0...0 }
        let needStart = max(0, start - edgeMargin)
        let firstK = needStart / chunkStride
        let needEnd = min(songSamples, end + edgeMargin)
        let lastK = needEnd <= segmentSamples ? 0 : (needEnd - segmentSamples + chunkStride - 1) / chunkStride
        return firstK...max(firstK, lastK)
    }

    private static func triangleWeight() -> [Float] {
        let half = segmentSamples / 2
        return vDSP.divide(
            vDSP.ramp(withInitialValue: 1, increment: 1, count: half)
                + vDSP.ramp(withInitialValue: Float(segmentSamples - half), increment: -1, count: segmentSamples - half),
            Float(half))
    }

    private static func windowSlice(channels: [[Float]], chunkIndex: Int, songSamples: Int) -> (window: [[Float]], offset: Int, trim: Int, count: Int) {
        let segment = segmentSamples
        if songSamples <= segment {
            let trim = (segment - songSamples) / 2
            let window = channels.map { ch -> [Float] in
                var samples = [Float](repeating: 0, count: segment)
                samples.replaceSubrange(trim..<(trim + songSamples), with: ch[0..<songSamples])
                return samples
            }
            return (window, 0, trim, songSamples)
        }
        let offset = chunkIndex * chunkStride
        let count = min(segment, max(0, songSamples - offset))
        let window = channels.map { ch -> [Float] in
            var samples = [Float](repeating: 0, count: segment)
            if count > 0 { samples.replaceSubrange(0..<count, with: ch[offset..<(offset + count)]) }
            return samples
        }
        return (window, offset, 0, count)
    }

    private static func computeAndStoreChunk(index: Int, sourceURL: URL, songSamples: Int,
                                             destination: URL, model: MLModel) throws -> ChunkStats {
        let segment = segmentSamples
        let window: [[Float]]
        if songSamples <= segment {
            let pcm = try readPCM(from: sourceURL, start: 0, count: songSamples)
            let trim = (segment - songSamples) / 2
            window = pcm.map { ch -> [Float] in
                var samples = [Float](repeating: 0, count: segment)
                samples.replaceSubrange(trim..<(trim + songSamples), with: ch[0..<songSamples])
                return samples
            }
        } else {
            let offset = index * chunkStride
            let available = min(segment, max(0, songSamples - offset))
            if available == segment {
                window = try readPCM(from: sourceURL, start: offset, count: segment)
            } else {
                let pcm = available > 0 ? try readPCM(from: sourceURL, start: offset, count: available) : [[], []]
                window = pcm.map { ch -> [Float] in
                    var samples = [Float](repeating: 0, count: segment)
                    if available > 0 { samples.replaceSubrange(0..<available, with: ch[0..<available]) }
                    return samples
                }
            }
        }
        let (vocals, instL, instR, stats) = try separateWindow(window, model: model)
        try writeChunkBinary(vocals: vocals, instL: instL, instR: instR, to: destination)
        return stats
    }

    private static func isChunkValid(_ url: URL) -> Bool {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        return size == chunkByteCount
    }

    private static func writeChunkBinary(vocals: [Float], instL: [Float], instR: [Float], to url: URL) throws {
        var data = Data(capacity: chunkByteCount)
        vocals.withUnsafeBytes { data.append(contentsOf: $0) }
        instL.withUnsafeBytes { data.append(contentsOf: $0) }
        instR.withUnsafeBytes { data.append(contentsOf: $0) }
        try data.write(to: url, options: .atomic)
    }

    private static func assemble(chunkRange: ClosedRange<Int>, songFolder: URL, songSamples: Int,
                                 fullStart: Int, fullCount: Int) throws -> (vocalsMono: [Float], instrumental: [[Float]]) {
        let weight = triangleWeight()
        var vocalsMono = [Float](repeating: 0, count: fullCount)
        var instLOut = [Float](repeating: 0, count: fullCount)
        var instROut = [Float](repeating: 0, count: fullCount)
        var total = [Float](repeating: 0, count: fullCount)
        let fullEnd = fullStart + fullCount
        let segment = segmentSamples

        for k in chunkRange {
            try autoreleasepool {
                let url = songFolder.appendingPathComponent("\(k).bin")
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                guard data.count == chunkByteCount else { throw CoreMLSeparationError.unreadable }

                let chunkStart: Int
                let bufferTrim: Int
                let chunkValidEnd: Int
                if songSamples <= segment {
                    chunkStart = 0
                    bufferTrim = (segment - songSamples) / 2
                    chunkValidEnd = songSamples
                } else {
                    chunkStart = k * chunkStride
                    bufferTrim = 0
                    chunkValidEnd = min(songSamples, chunkStart + segment)
                }
                let lo = max(fullStart, chunkStart)
                let hi = min(fullEnd, chunkValidEnd)
                let count = hi - lo
                guard count > 0 else { return }

                let srcOffset = bufferTrim + (lo - chunkStart)
                let dstOffset = lo - fullStart

                data.withUnsafeBytes { raw in
                    let base = raw.bindMemory(to: Float.self).baseAddress!
                    let vPtr = base
                    let iLPtr = base + segment
                    let iRPtr = base + 2 * segment
                    weight.withUnsafeBufferPointer { wPtr in
                        total.withUnsafeMutableBufferPointer { tOut in
                            vDSP_vadd(wPtr.baseAddress! + srcOffset, 1, tOut.baseAddress! + dstOffset, 1,
                                      tOut.baseAddress! + dstOffset, 1, vDSP_Length(count))
                        }
                        vocalsMono.withUnsafeMutableBufferPointer { out in
                            vDSP_vma(vPtr + srcOffset, 1, wPtr.baseAddress! + srcOffset, 1,
                                     out.baseAddress! + dstOffset, 1, out.baseAddress! + dstOffset, 1, vDSP_Length(count))
                        }
                        instLOut.withUnsafeMutableBufferPointer { out in
                            vDSP_vma(iLPtr + srcOffset, 1, wPtr.baseAddress! + srcOffset, 1,
                                     out.baseAddress! + dstOffset, 1, out.baseAddress! + dstOffset, 1, vDSP_Length(count))
                        }
                        instROut.withUnsafeMutableBufferPointer { out in
                            vDSP_vma(iRPtr + srcOffset, 1, wPtr.baseAddress! + srcOffset, 1,
                                     out.baseAddress! + dstOffset, 1, out.baseAddress! + dstOffset, 1, vDSP_Length(count))
                        }
                    }
                }
            }
        }
        // If fullCount extended past songSamples (rounding), keep any uncovered tail at 0 cleanly.
        var floor: Float = 1e-8
        var safeTotal = [Float](repeating: 0, count: fullCount)
        vDSP_vthr(total, 1, &floor, &safeTotal, 1, vDSP_Length(fullCount))
        return (vDSP.divide(vocalsMono, safeTotal), [vDSP.divide(instLOut, safeTotal), vDSP.divide(instROut, safeTotal)])
    }

    private static func accumulate(vocals: [Float], instL: [Float], instR: [Float], weight: [Float],
                                   srcOffset: Int, dstOffset: Int, count: Int,
                                   total: inout [Float], vocalsMono: inout [Float],
                                   instLOut: inout [Float], instROut: inout [Float]) {
        guard count > 0 else { return }
        weight.withUnsafeBufferPointer { w in
            total.withUnsafeMutableBufferPointer { t in
                vDSP_vadd(w.baseAddress! + srcOffset, 1, t.baseAddress! + dstOffset, 1, t.baseAddress! + dstOffset, 1, vDSP_Length(count))
            }
            vocals.withUnsafeBufferPointer { v in
                vocalsMono.withUnsafeMutableBufferPointer { out in
                    vDSP_vma(v.baseAddress! + srcOffset, 1, w.baseAddress! + srcOffset, 1,
                             out.baseAddress! + dstOffset, 1, out.baseAddress! + dstOffset, 1, vDSP_Length(count))
                }
            }
            instL.withUnsafeBufferPointer { iL in
                instLOut.withUnsafeMutableBufferPointer { out in
                    vDSP_vma(iL.baseAddress! + srcOffset, 1, w.baseAddress! + srcOffset, 1,
                             out.baseAddress! + dstOffset, 1, out.baseAddress! + dstOffset, 1, vDSP_Length(count))
                }
            }
            instR.withUnsafeBufferPointer { iR in
                instROut.withUnsafeMutableBufferPointer { out in
                    vDSP_vma(iR.baseAddress! + srcOffset, 1, w.baseAddress! + srcOffset, 1,
                             out.baseAddress! + dstOffset, 1, out.baseAddress! + dstOffset, 1, vDSP_Length(count))
                }
            }
        }
    }

    // MARK: - Strided copies (vDSP)

    /// Frames (each ≥ `bins` values) → one (frame, bin) row-major matrix of the first `bins` values.
    private static func frameMajor(_ frames: [[Float]], bins: Int) -> [Float] {
        var matrix = [Float]()
        matrix.reserveCapacity(frames.count * bins)
        for frame in frames { matrix.append(contentsOf: frame[0..<bins]) }
        return matrix
    }

    private static func copy(_ values: [Float], to destination: UnsafeMutablePointer<Float>, stride: Int) {
        var zero: Float = 0
        // Strided copy: destination[i * stride] = values[i] + 0.
        vDSP_vsadd(values, 1, &zero, destination, vDSP_Stride(stride), vDSP_Length(values.count))
    }

    /// (frame, bin) matrix → a model plane laid out with the given (bin, frame) strides.
    private static func writePlane(_ matrix: [Float], to destination: UnsafeMutablePointer<Float>,
                                   binStride: Int, frameStride: Int, bins: Int, frames: Int) {
        guard frameStride == 1 else {
            for t in 0..<frames {
                for b in 0..<bins { destination[b * binStride + t * frameStride] = matrix[t * bins + b] }
            }
            return
        }
        if binStride == frames {
            vDSP_mtrans(matrix, 1, destination, 1, vDSP_Length(bins), vDSP_Length(frames))
        } else {
            var transposed = [Float](repeating: 0, count: bins * frames)
            vDSP_mtrans(matrix, 1, &transposed, 1, vDSP_Length(bins), vDSP_Length(frames))
            vDSP_mmov(transposed, destination, vDSP_Length(frames), vDSP_Length(bins), vDSP_Length(frames), vDSP_Length(binStride))
        }
    }

    /// A model plane with the given (bin, frame) strides → a (frame, bin) row-major matrix.
    private static func readPlane(_ source: UnsafePointer<Float>, binStride: Int, frameStride: Int,
                                  bins: Int, frames: Int) -> [Float] {
        var matrix = [Float](repeating: 0, count: bins * frames)
        guard frameStride == 1 else {
            for t in 0..<frames {
                for b in 0..<bins { matrix[t * bins + b] = source[b * binStride + t * frameStride] }
            }
            return matrix
        }
        if binStride == frames {
            vDSP_mtrans(source, 1, &matrix, 1, vDSP_Length(frames), vDSP_Length(bins))
        } else {
            var packed = [Float](repeating: 0, count: bins * frames)
            vDSP_mmov(source, &packed, vDSP_Length(frames), vDSP_Length(bins), vDSP_Length(binStride), vDSP_Length(frames))
            vDSP_mtrans(packed, 1, &matrix, 1, vDSP_Length(frames), vDSP_Length(bins))
        }
        return matrix
    }

    // MARK: - Audio files

    /// Decodes the whole song once to a sample-exact 44.1 kHz stereo Float32 CAF file so every
    /// chunk and trimmed mix shares the exact same sample alignment (even for VBR MP3s).
    fileprivate static func decodeSongToPCM(asset: AVAsset, track: AVAssetTrack, destination: URL) throws -> Int {
        guard let reader = try? AVAssetReader(asset: asset) else { throw CoreMLSeparationError.unreadable }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false, AVLinearPCMIsBigEndianKey: false,
            AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 2,
        ])
        guard reader.canAdd(output) else { throw CoreMLSeparationError.unreadable }
        reader.add(output)
        guard reader.startReading() else { throw CoreMLSeparationError.unreadable }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let partial = destination.deletingLastPathComponent().appendingPathComponent("source.partial-\(UUID().uuidString).caf")
        defer { try? fileManager.removeItem(at: partial) }

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            throw CoreMLSeparationError.unreadable
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let outFile = try AVAudioFile(forWriting: partial, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        var totalFrames = 0
        var scratchBuffer: AVAudioPCMBuffer?

        while let sampleBuffer = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(sampleBuffer) {
            let length = CMBlockBufferGetDataLength(block)
            let sampleCount = length / MemoryLayout<Float>.size
            let frameCount = sampleCount / 2
            guard frameCount > 0 else { continue }
            var interleaved = [Float](repeating: 0, count: sampleCount)
            interleaved.withUnsafeMutableBytes { _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
            if scratchBuffer == nil || Int(scratchBuffer!.frameCapacity) < frameCount {
                scratchBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(frameCount, 65_536)))
            }
            guard let pcm = scratchBuffer, let channels = pcm.floatChannelData else { throw CoreMLSeparationError.unreadable }
            pcm.frameLength = AVAudioFrameCount(frameCount)
            var split = DSPSplitComplex(realp: channels[0], imagp: channels[1])
            interleaved.withUnsafeBytes {
                vDSP_ctoz($0.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(frameCount))
            }
            try outFile.write(from: pcm)
            totalFrames += frameCount
        }
        guard reader.status == .completed, totalFrames > 0 else { throw CoreMLSeparationError.unreadable }
        if !fileManager.fileExists(atPath: destination.path) {
            try fileManager.moveItem(at: partial, to: destination)
        }
        return totalFrames
    }

    private static func readPCM(from url: URL, start: Int, count: Int) throws -> [[Float]] {
        let file = try AVAudioFile(forReading: url)
        let fileLength = Int(file.length)
        var left = [Float](repeating: 0, count: count)
        var right = [Float](repeating: 0, count: count)
        let available = min(count, max(0, fileLength - start))
        guard available > 0 else { return [left, right] }

        file.framePosition = AVAudioFramePosition(start)
        let chunkFrames: AVAudioFrameCount = 65_536
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunkFrames) else {
            throw CoreMLSeparationError.unreadable
        }
        var copied = 0
        while copied < available {
            let toRead = AVAudioFrameCount(min(Int(chunkFrames), available - copied))
            buffer.frameLength = 0
            try file.read(into: buffer, frameCount: toRead)
            let got = Int(buffer.frameLength)
            guard got > 0, let channels = buffer.floatChannelData else { break }
            left.withUnsafeMutableBufferPointer { dst in
                (dst.baseAddress! + copied).update(from: channels[0], count: got)
            }
            right.withUnsafeMutableBufferPointer { dst in
                (dst.baseAddress! + copied).update(from: channels[1], count: got)
            }
            copied += got
        }
        return [left, right]
    }

    private static func stems(in folder: URL) -> SeparatedStems {
        SeparatedStems(mixURL: folder.appendingPathComponent("mix.wav"),
                       vocalGuideURL: folder.appendingPathComponent("vocals.wav"),
                       instrumentalURL: folder.appendingPathComponent("instrumental.wav"),
                       method: .coreML)
    }

    private static func isCached(_ stems: SeparatedStems) -> Bool {
        [stems.mixURL, stems.vocalGuideURL, stems.instrumentalURL].allSatisfy { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func writeStems(mix: [[Float]], vocalsMono: [Float], instrumental: [[Float]],
                                   to folder: URL, stems: SeparatedStems) throws {
        // Written to a scratch folder and moved in whole: a separation stopped half way
        // (app killed while writing) must never leave stems that look complete.
        let fileManager = FileManager.default
        let scratch = folder.deletingLastPathComponent()
            .appendingPathComponent(folder.lastPathComponent + ".partial-" + UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: scratch, withIntermediateDirectories: true)
        do {
            try Self.write(mix, to: scratch.appendingPathComponent(stems.mixURL.lastPathComponent))
            try Self.write([vocalsMono], to: scratch.appendingPathComponent(stems.vocalGuideURL.lastPathComponent))
            try Self.write(instrumental, to: scratch.appendingPathComponent(stems.instrumentalURL.lastPathComponent))
            try? fileManager.removeItem(at: folder)
            try fileManager.moveItem(at: scratch, to: folder)
        } catch {
            try? fileManager.removeItem(at: scratch)
            throw error
        }
    }

    private static func write(_ channels: [[Float]], to url: URL) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(channels.count)),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(channels[0].count)) else {
            throw CoreMLSeparationError.unreadable
        }
        buffer.frameLength = AVAudioFrameCount(channels[0].count)
        for (c, channel) in channels.enumerated() {
            channel.withUnsafeBufferPointer { buffer.floatChannelData![c].update(from: $0.baseAddress!, count: channel.count) }
        }
        try? FileManager.default.removeItem(at: url)
        try AVAudioFile(forWriting: url, settings: format.settings).write(from: buffer)
    }

    fileprivate static func pruneChunkFolders(in root: URL, keeping activeKey: String) {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles
        ) else { return }
        let sorted = entries.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da > db
        }
        for folder in sorted.dropFirst(maxCachedSongChunkFolders) where folder.lastPathComponent != activeKey {
            try? fileManager.removeItem(at: folder)
        }
    }

    private static func songCacheKey(_ url: URL) -> String {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        return fnv1a("\(url.standardizedFileURL.path)|\(modified)")
    }

    private static func cacheKey(_ url: URL, _ trim: ClosedRange<TimeInterval>) -> String {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        return fnv1a("\(url.standardizedFileURL.path)|\(modified)|\(trim.lowerBound)|\(trim.upperBound)")
    }

    private static func fnv1a(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    // MARK: - Concurrency coordinator

    /// Serializes GPU CoreML predictions and deduplicates in-flight decodes/chunks between
    /// background pre-separation and foreground `separateStems`.
    private actor ChunkCoordinator {
        struct ChunkID: Hashable, Sendable {
            let songKey: String
            let index: Int
        }

        private var inFlightSources: [String: Task<(url: URL, samples: Int), any Error>] = [:]
        private var inFlightChunks: [ChunkID: Task<ChunkStats, any Error>] = [:]
        private var gpuTail: Task<Void, Never>?

        func ensureDecodedSource(songKey: String, songFolder: URL, asset: AVAsset, track: AVAssetTrack,
                                 chunksRoot: URL) async throws -> (url: URL, samples: Int) {
            let sourceURL = songFolder.appendingPathComponent("source.caf")
            if FileManager.default.fileExists(atPath: sourceURL.path),
               let file = try? AVAudioFile(forReading: sourceURL), file.length > 0 {
                try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: songFolder.path)
                return (sourceURL, Int(file.length))
            }
            if let existing = inFlightSources[songKey], let source = try? await existing.value {
                return source
            }
            let task = Task.detached(priority: .userInitiated) { () -> (url: URL, samples: Int) in
                let samples = try HTDemucsStemSeparationRepository.decodeSongToPCM(asset: asset, track: track, destination: sourceURL)
                HTDemucsStemSeparationRepository.pruneChunkFolders(in: chunksRoot, keeping: songKey)
                return (sourceURL, samples)
            }
            inFlightSources[songKey] = task
            defer { inFlightSources[songKey] = nil }
            return try await task.value
        }

        /// Runs `work` serially on the GPU if `key` is not already in flight. Returns `nil` when
        /// another caller already computed the chunk (caller awaited that work instead of repeating it).
        func computeChunkIfNeeded(key: ChunkID, priority: TaskPriority,
                                  work: @escaping @Sendable () throws -> ChunkStats) async throws -> ChunkStats? {
            if let existing = inFlightChunks[key], (try? await existing.value) != nil {
                return nil
            }
            let previous = gpuTail
            let task = Task.detached(priority: priority) { () -> ChunkStats in
                await previous?.value
                return try work()
            }
            gpuTail = Task { _ = try? await task.value }
            inFlightChunks[key] = task
            defer { inFlightChunks[key] = nil }
            return try await task.value
        }
    }
}
