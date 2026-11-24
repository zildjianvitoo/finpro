//
//  MicrophonePitchSource.swift
//  finpro
//
//  Headset microphone → CREPE pitch for the vocal range test.
//  Engine lifecycle and route changes are serialised; no silent fallback to iPhone input.
//

import Accelerate
import AVFoundation
import OSLog

nonisolated final class MicrophonePitchSource: LivePitchSource, MicrophoneInputProviding, @unchecked Sendable {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "finpro", category: "VocalMic")
    private var engine: AVAudioEngine?
    private let worker = PitchWorker()
    private let queue = DispatchQueue(label: "vocal-range.microphone", qos: .userInitiated)
    private let lock = NSLock()
    private var continuation: AsyncStream<PitchSample>.Continuation?
    private var routeObserver: NSObjectProtocol?
    private var hasTap = false
    private var generation = UUID()
    private var activeMicrophoneName: String?

    var microphoneName: String? { lock.withLock { activeMicrophoneName } }
    var isHeadsetMicrophoneActive: Bool { lock.withLock { activeMicrophoneName != nil } }

    func start() async throws -> AsyncStream<PitchSample> {
        try await start(levelOnly: false)
    }

    func startLevelMonitoring() async throws -> AsyncStream<PitchSample> {
        try await start(levelOnly: true)
    }

    private func start(levelOnly: Bool) async throws -> AsyncStream<PitchSample> {
        let startedAt = ContinuousClock.now
        Self.log.notice("Starting vocal mic: level-only=\(levelOnly)")
        let token = beginNewGeneration()
        queue.async { [self] in stopAudioOnQueue() }
        if !levelOnly { try await worker.prepare() }
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { result in
            queue.async { [self] in
                do {
                    guard self.isCurrent(token) else { throw CancellationError() }
                    Self.log.notice("Activating vocal audio session")
                    let microphoneUID = try HeadsetMicrophoneSession.activate(mode: .measurement)
                    let (stream, continuation) = AsyncStream.makeStream(of: PitchSample.self, bufferingPolicy: .bufferingNewest(64))
                    let kept = self.lock.withLock { () -> Bool in
                        guard self.generation == token else { return false }
                        self.continuation = continuation
                        return true
                    }
                    guard kept else { throw CancellationError() }
                    let engine = self.engine ?? {
                        let created = AVAudioEngine()
                        self.engine = created
                        return created
                    }()
                    let input = engine.inputNode
                    let format = input.outputFormat(forBus: 0)
                    guard format.sampleRate > 0, format.channelCount > 0 else { throw HeadsetMicrophoneError.unavailable }
                    // 4096 frames become 256 ms at 16 kHz, making Bluetooth range feedback
                    // arrive in bursts. Request the same time interval at every input rate.
                    let tapBufferSize = AVAudioFrameCount(max(1, (format.sampleRate * AppConfiguration.default.pitchHop).rounded()))
                    input.installTap(onBus: 0, bufferSize: tapBufferSize, format: format) { [weak self] buffer, time in
                        guard let self else { return }
                        let start = time.isHostTimeValid ? AVAudioTime.seconds(forHostTime: time.hostTime) : ProcessInfo.processInfo.systemUptime
                        if levelOnly {
                            guard self.isCurrent(token),
                                  let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
                            let stride = buffer.format.isInterleaved ? Int(buffer.format.channelCount) : 1
                            var rms: Float = 0
                            vDSP_rmsqv(channel, stride, &rms, vDSP_Length(buffer.frameLength))
                            continuation.yield(PitchSample(
                                captureTime: CMTime(seconds: start, preferredTimescale: 60_000),
                                frequency: nil, rmsDecibels: rms > 0 ? 20 * log10(rms) : -.infinity))
                            return
                        }
                        self.worker.accept(buffer, start: start) { [weak self] estimate, frameStart, _, failure in
                            guard failure == nil else { return }
                            let decibels = estimate.rms > 0 ? Float(20 * log10(estimate.rms)) : -.infinity
                            let sample = PitchSample(captureTime: CMTime(seconds: frameStart + estimate.centerOffset, preferredTimescale: 60_000),
                                                     frequency: estimate.frequency.map(Float.init), rmsDecibels: decibels)
                            self?.lock.withLock { self?.continuation }?.yield(sample)
                        }
                    }
                    self.hasTap = true
                    engine.prepare()
                    try engine.start()
                    try HeadsetMicrophoneSession.verify(microphoneUID)
                    let portName = HeadsetMicrophoneSession.currentInput?.portName
                    self.lock.withLock {
                        if self.generation == token { self.activeMicrophoneName = portName }
                    }
                    self.routeObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { [weak self] _ in
                        guard let self else { return }
                        self.queue.async {
                            guard self.isCurrent(token) else { return }
                            if HeadsetMicrophoneSession.currentInput?.uid != microphoneUID {
                                _ = self.beginNewGeneration()
                                self.stopAudioOnQueue()
                            }
                        }
                    }
                    let elapsed = (ContinuousClock.now - startedAt) / .seconds(1)
                    Self.log.notice("Vocal mic started in \(elapsed, format: .fixed(precision: 3)) s")
                    result.resume(returning: stream)
                } catch {
                    if !(error is CancellationError) {
                        Self.log.error("Vocal mic start failed: \(error.localizedDescription, privacy: .public)")
                    }
                    if self.isCurrent(token) {
                        _ = self.beginNewGeneration()
                        self.stopAudioOnQueue()
                    }
                    result.resume(throwing: error)
                }
            }
        }
    }

    func stop() {
        _ = beginNewGeneration()
        queue.async { [self] in stopAudioOnQueue() }
    }

    private func isCurrent(_ token: UUID) -> Bool {
        lock.withLock { generation == token }
    }

    private func beginNewGeneration() -> UUID {
        lock.withLock {
            let token = UUID()
            generation = token
            continuation?.finish()
            continuation = nil
            activeMicrophoneName = nil
            return token
        }
    }

    private func stopAudioOnQueue() {
        if let routeObserver {
            NotificationCenter.default.removeObserver(routeObserver)
            self.routeObserver = nil
        }
        if let engine {
            if engine.isRunning { engine.stop() }
            if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
