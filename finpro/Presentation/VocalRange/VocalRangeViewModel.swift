//
//  VocalRangeViewModel.swift
//  finpro
//

import CoreMedia
import Foundation
import Observation

@Observable
final class VocalRangeViewModel {
    enum Prompt: Int, Equatable, CaseIterable {
        case lowest, highest
    }

    enum Status: Equatable {
        case idle
        case listening
        case captured(Float)
        case finished(VocalRange)
        case failed(UserFacingError)
    }

    private(set) var prompt: Prompt = .lowest
    private(set) var status: Status = .idle
    private(set) var liveMIDI: Float?
    private(set) var holdProgress: Double = 0
    private(set) var lowestMIDI: Float?
    private(set) var highestMIDI: Float?
    private(set) var waveformLevels: [Float] = []
    private(set) var hasStartedListening = false
    private(set) var microphoneName: String?

    @ObservationIgnored private let source: any LivePitchSource
    @ObservationIgnored private let repository: any VocalRangeRepository
    @ObservationIgnored private let configuration: AppConfiguration
    @ObservationIgnored private let onSaved: () -> Void
    @ObservationIgnored private var listening: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()

    init(source: any LivePitchSource, repository: any VocalRangeRepository,
         configuration: AppConfiguration, onSaved: @escaping () -> Void) {
        self.source = source
        self.repository = repository
        self.configuration = configuration
        self.onSaved = onSaved
    }

    func listen() { startListening() }

    func monitorWarmup() { startListening(waveformOnly: true) }

    /// Clears only the current input, keeping the measured range.
    func resetCapture() {
        stopListening()
        status = .idle
        holdProgress = 0
        liveMIDI = nil
        hasStartedListening = false
        waveformLevels = []
    }

    private func startListening(waveformOnly: Bool = false) {
        stopListening()
        if !waveformOnly { hasStartedListening = true }
        waveformLevels = []
        let token = generation
        if !waveformOnly { status = .listening }
        microphoneName = nil
        holdProgress = 0
        liveMIDI = nil
        listening = Task { [weak self] in
            guard let self else { return }
            do {
                #if DEBUG
                // Keep simulator samples tied to the prompt across retries and Redo Test.
                (source as? FakeLivePitchSource)?.selectNote(at: prompt.rawValue)
                #endif
                let samples = try await (waveformOnly ? source.startLevelMonitoring() : source.start())
                microphoneName = (source as? any MicrophoneInputProviding)?.microphoneName
                var display = StabilizePitchDisplayUseCase(configuration: configuration)
                var detector = DetectVocalRangeUseCase(configuration: configuration, duration: configuration.vocalRangeHoldDuration)
                for await sample in samples {
                    guard !Task.isCancelled, generation == token else { return }
                    let amplitude = sample.rmsDecibels.isFinite
                        ? min(1, max(0, (sample.rmsDecibels - configuration.noiseGateDBFS)
                            / max(1, configuration.vocalWaveformCeilingDBFS - configuration.noiseGateDBFS))) : 0
                    waveformLevels.append(amplitude)
                    if waveformLevels.count > configuration.vocalWaveformFrameCount { waveformLevels.removeFirst() }
                    guard !waveformOnly else { continue }
                    let note = detector.ingest(sample)
                    liveMIDI = display.execute(midi: detector.latestMIDI, time: sample.captureTime.seconds)
                    holdProgress = min(1, detector.stableDuration / configuration.vocalRangeHoldDuration)
                    if let note {
                        captured(note)
                        break
                    }
                }
                guard generation == token, !Task.isCancelled else { return }
                if case .listening = status {
                    let input = source as? any MicrophoneInputProviding
                    status = .failed(input?.isHeadsetMicrophoneActive == false ? .headsetMicrophoneRequired : .vocalRangeCaptureFailed)
                }
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                if !waveformOnly {
                    status = .failed((error as? any UserFacingConvertible)?.userFacingError ?? .vocalRangeCaptureFailed)
                }
            }
            if generation == token { source.stop() }
        }
    }

    func next() {
        guard case .captured = status else { return }
        stopListening()
        if let next = Prompt(rawValue: prompt.rawValue + 1) {
            prompt = next
            hasStartedListening = false
            status = .idle
            holdProgress = 0
            liveMIDI = nil
        }
    }

    /// Result screen, back: sing the highest note again; the lowest note is kept.
    func redoHighest() {
        stopListening()
        guard lowestMIDI != nil else { return restart() }
        highestMIDI = nil
        prompt = .highest
        hasStartedListening = false
        holdProgress = 0
        liveMIDI = nil
        status = .idle
    }

    func save() {
        guard case .finished(let range) = status else { return }
        repository.save(range)
        onSaved()
    }

    func restart() {
        stopListening()
        prompt = .lowest
        hasStartedListening = false
        lowestMIDI = nil
        highestMIDI = nil
        microphoneName = nil
        holdProgress = 0
        liveMIDI = nil
        status = .idle
    }

    func stopListening() {
        generation = UUID()
        listening?.cancel()
        listening = nil
        source.stop()
    }

    private func captured(_ note: Float) {
        holdProgress = 1
        switch prompt {
        case .lowest:
            lowestMIDI = note
        case .highest:
            guard let low = lowestMIDI, note - low >= configuration.minimumVocalRangeSpan else {
                status = .failed(.vocalRangeTooNarrow)
                return
            }
            highestMIDI = note
            status = .finished(VocalRange(lowestMIDI: low, highestMIDI: note))
            return
        }
        status = .captured(note)
    }
}
