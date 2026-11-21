//
//  CrepePitchDetector.swift
//  finpro
//
//  CREPE tiny (CoreML) pitch estimate for one audio window. Used for live pitch,
//  the vocal range test and the guide fallback (PRD §2, team decision 2026-11-01).
//

import Accelerate
import AVFoundation
import CoreML
import Foundation

nonisolated final class CrepePitchDetector {
  /// CREPE's own voicing threshold on the salience peak (model-specific, PRD §2).
  static let confidenceThreshold = 0.5
  /// Windows quieter than this skip inference. The configurable noise gate is applied later
  /// in TrackLivePitchUseCase; this only saves work on near-silence (−60 dBFS).
  static let minimumRMS = 0.001
  private let model: MLModel
  /// Reused between frames (creating one per frame was slow enough to make the worker fall behind).
  private var cachedConverter: (rate: Double, converter: AVAudioConverter)?
  init(modelURL: URL? = nil) throws {
    guard let url = modelURL ?? Bundle.main.url(forResource: "CrepeTiny", withExtension: "mlmodelc")
    else {
      throw NSError(
        domain: "CREPE", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "CREPE model not found in the app bundle."])
    }
    let config = MLModelConfiguration()
    // Neural Engine first: during recording the CPU is also encoding video and drawing the piano
    // roll, and running CREPE there 20× per second made playback crackle under load.
    config.computeUnits = .cpuAndNeuralEngine
    model = try MLModel(contentsOf: url, configuration: config)
  }
  /// Loads the model and runs it on a voiced tone a few times: the first CoreML predictions are
  /// slow, and later detectors reuse the compiled model (ModelPrewarmer, at app start).
  static func prewarm(modelURL: URL? = nil) throws {
    let detector = try CrepePitchDetector(modelURL: modelURL)
    let rate = 48_000.0
    let tone = (0..<4096).map { Float(0.3 * sin(2 * Double.pi * 220 * Double($0) / rate)) }
    for _ in 0..<3 { _ = try detector.analyze(tone, sampleRate: rate) }
  }

  func detect(_ samples: [Float], sampleRate: Double) throws -> Double? {
    try analyze(samples, sampleRate: sampleRate).frequency
  }
  private func converter(from source: AVAudioFormat, to target: AVAudioFormat) -> AVAudioConverter? {
    if let cached = cachedConverter, cached.rate == source.sampleRate {
      cached.converter.reset()
      return cached.converter
    }
    guard let converter = AVAudioConverter(from: source, to: target) else { return nil }
    cachedConverter = (source.sampleRate, converter)
    return converter
  }
  func analyze(_ samples: [Float], sampleRate: Double) throws -> CrepeEstimate {
    guard sampleRate > 0, !samples.isEmpty else { return CrepeEstimate() }
    guard
      let sourceFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
      let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
      let source = AVAudioPCMBuffer(
        pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(samples.count)),
      let converter = converter(from: sourceFormat, to: targetFormat),
      let output = AVAudioPCMBuffer(
        pcmFormat: targetFormat,
        frameCapacity: AVAudioFrameCount(ceil(Double(samples.count) * 16000 / sampleRate) + 256))
    else {
      throw NSError(
        domain: "CREPE", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Unsupported audio format for CREPE."])
    }
    source.frameLength = AVAudioFrameCount(samples.count)
    samples.withUnsafeBufferPointer {
      source.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count)
    }
    var supplied = false
    var conversionError: NSError?
    converter.primeMethod = .none
    let status = converter.convert(to: output, error: &conversionError) { _, state in
      if supplied {
        state.pointee = .endOfStream
        return nil
      }
      supplied = true
      state.pointee = .haveData
      return source
    }
    if let conversionError { throw conversionError }
    guard status != .error, output.frameLength >= 1024 else { return CrepeEstimate() }
    let offset = (Int(output.frameLength) - 1024) / 2
    let channel = output.floatChannelData![0]
    let frame = (0..<1024).map { Double(channel[offset + $0]) }
    let mean = frame.reduce(0, +) / 1024
    let variance = frame.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / 1024
    let deviation = sqrt(variance)
    var estimate = CrepeEstimate()
    estimate.rms = deviation
    estimate.centerOffset = Double(offset + 512) / 16000
    guard deviation > Self.minimumRMS else { return estimate }
    let input = try MLMultiArray(shape: [1, 1024], dataType: .float32)
    let inputPtr = input.dataPointer.bindMemory(to: Float.self, capacity: 1024)
    for i in 0..<1024 { inputPtr[i] = Float((frame[i] - mean) / deviation) }
    let features = try MLDictionaryFeatureProvider(dictionary: [
      "audio": MLFeatureValue(multiArray: input)
    ])
    let result = try model.prediction(from: features)
    guard let salience = result.featureValue(for: "salience")?.multiArrayValue,
      salience.count == 360
    else {
      throw NSError(
        domain: "CREPE", code: 3,
        userInfo: [NSLocalizedDescriptionKey: "Unexpected CREPE model output."])
    }
    Self.decodeSalience(salience, into: &estimate)
    return estimate
  }

  /// Offline batch analysis of a whole mono track: resamples once to 16 kHz, skips silent frames,
  /// and runs CoreML in batches via raw Float pointers (no per-frame AVAudioConverter or NSNumber boxing).
  func analyzeTrack(
    _ samples: [Float],
    sampleRate: Double,
    hop: TimeInterval,
    windowDuration: TimeInterval,
    batchSize: Int = 64
  ) throws -> [(time: TimeInterval, estimate: CrepeEstimate)] {
    guard sampleRate > 0, !samples.isEmpty else { return [] }
    let window = Int((sampleRate * windowDuration).rounded(.up))
    let step = max(1, Int((sampleRate * hop).rounded()))
    guard samples.count >= window else { return [] }

    let resampled = try resampleTo16k(samples, sampleRate: sampleRate)
    guard resampled.count >= 1024 else { return [] }

    let frameCount = (samples.count - window) / step + 1
    let halfWindow = windowDuration / 2
    var results: [(time: TimeInterval, estimate: CrepeEstimate)] = []
    results.reserveCapacity(frameCount)

    var pendingIndices: [Int] = []
    var pendingProviders: [MLFeatureProvider] = []
    pendingIndices.reserveCapacity(batchSize)
    pendingProviders.reserveCapacity(batchSize)

    func flushBatch() throws {
      guard !pendingProviders.isEmpty else { return }
      try Task.checkCancellation()
      let batch = MLArrayBatchProvider(array: pendingProviders)
      let outputs = try model.predictions(from: batch, options: MLPredictionOptions())
      for (slot, resultIndex) in pendingIndices.enumerated() {
        let out = outputs.features(at: slot)
        guard let salience = out.featureValue(for: "salience")?.multiArrayValue,
          salience.count == 360
        else {
          throw NSError(
            domain: "CREPE", code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Unexpected CREPE model output."])
        }
        Self.decodeSalience(salience, into: &results[resultIndex].estimate)
      }
      pendingIndices.removeAll(keepingCapacity: true)
      pendingProviders.removeAll(keepingCapacity: true)
    }

    var mean: Float = 0
    var deviation: Float = 0
    let maxOffset = resampled.count - 1024

    for index in 0..<frameCount {
      let startSample = index * step
      let time = Double(startSample) / sampleRate + halfWindow
      let center16k = Int((time * 16_000).rounded())
      let offset = min(max(0, center16k - 512), maxOffset)

      let input = try MLMultiArray(shape: [1, 1024], dataType: .float32)
      let dst = input.dataPointer.bindMemory(to: Float.self, capacity: 1024)
      resampled.withUnsafeBufferPointer { src in
        // vDSP_normalize computes mean and population stddev and writes (x - mean) / stddev.
        vDSP_normalize(src.baseAddress! + offset, 1, dst, 1, &mean, &deviation, 1024)
      }

      var estimate = CrepeEstimate()
      estimate.rms = Double(deviation)
      estimate.centerOffset = halfWindow
      results.append((time, estimate))

      guard Double(deviation) > Self.minimumRMS, deviation.isFinite else { continue }
      let provider = try MLDictionaryFeatureProvider(dictionary: [
        "audio": MLFeatureValue(multiArray: input)
      ])
      pendingIndices.append(index)
      pendingProviders.append(provider)
      if pendingProviders.count >= batchSize {
        try flushBatch()
      }
    }
    try flushBatch()
    return results
  }

  private func resampleTo16k(_ samples: [Float], sampleRate: Double) throws -> [Float] {
    if abs(sampleRate - 16_000) < 1e-6 { return samples }
    guard
      let sourceFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
      let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
      let converter = converter(from: sourceFormat, to: targetFormat)
    else {
      throw NSError(
        domain: "CREPE", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Unsupported audio format for CREPE."])
    }
    converter.primeMethod = .none
    let expectedOut = Int(ceil(Double(samples.count) * 16_000 / sampleRate)) + 256
    var outSamples: [Float] = []
    outSamples.reserveCapacity(expectedOut)

    let chunkSize = 65_536
    guard
      let inBuffer = AVAudioPCMBuffer(
        pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(chunkSize)),
      let outBuffer = AVAudioPCMBuffer(
        pcmFormat: targetFormat, frameCapacity: AVAudioFrameCount(chunkSize))
    else {
      throw NSError(
        domain: "CREPE", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Unsupported audio format for CREPE."])
    }

    var readOffset = 0
    var conversionError: NSError?
    while true {
      outBuffer.frameLength = 0
      let status = converter.convert(to: outBuffer, error: &conversionError) { _, state in
        guard readOffset < samples.count else {
          state.pointee = .endOfStream
          return nil
        }
        let count = min(chunkSize, samples.count - readOffset)
        inBuffer.frameLength = AVAudioFrameCount(count)
        samples.withUnsafeBufferPointer { src in
          inBuffer.floatChannelData![0].update(from: src.baseAddress! + readOffset, count: count)
        }
        readOffset += count
        state.pointee = .haveData
        return inBuffer
      }
      if let conversionError { throw conversionError }
      let produced = Int(outBuffer.frameLength)
      if produced > 0, let ptr = outBuffer.floatChannelData?[0] {
        outSamples.append(contentsOf: UnsafeBufferPointer(start: ptr, count: produced))
      }
      if status == .endOfStream || status == .error || produced == 0 { break }
    }
    return outSamples
  }

  private static func decodeSalience(_ salience: MLMultiArray, into estimate: inout CrepeEstimate) {
    let values: [Double]
    if salience.dataType == .float32, salience.strides.last?.intValue == 1 {
      let ptr = salience.dataPointer.bindMemory(to: Float.self, capacity: 360)
      var peak = 0
      var peakValue = ptr[0]
      for i in 1..<360 where ptr[i] > peakValue {
        peakValue = ptr[i]
        peak = i
      }
      estimate.confidence = Double(peakValue)
      guard Double(peakValue) >= Self.confidenceThreshold else { return }
      var sum = 0.0
      var weighted = 0.0
      for i in max(0, peak - 4)...min(359, peak + 4) {
        let v = Double(ptr[i])
        sum += v
        weighted += v * (1997.3794084376191 + 20 * Double(i))
      }
      guard sum > 0 else { return }
      let hz = 10 * pow(2, weighted / sum / 1200)
      estimate.frequency = hz.isFinite ? hz : nil
      return
    } else {
      values = (0..<360).map { salience[$0].doubleValue }
    }
    guard let peak = values.indices.max(by: { values[$0] < values[$1] }) else { return }
    estimate.confidence = values[peak]
    guard values[peak] >= Self.confidenceThreshold else { return }
    var sum = 0.0
    var weighted = 0.0
    for i in max(0, peak - 4)...min(359, peak + 4) {
      sum += values[i]
      weighted += values[i] * (1997.3794084376191 + 20 * Double(i))
    }
    guard sum > 0 else { return }
    let hz = 10 * pow(2, weighted / sum / 1200)
    estimate.frequency = hz.isFinite ? hz : nil
  }
}
