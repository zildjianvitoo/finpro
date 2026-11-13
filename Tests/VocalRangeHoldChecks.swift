// Standalone checks for the v2 vocal range flow. Not bundled with the app.
import CoreMedia
import Foundation

nonisolated final class RangePitchSource: LivePitchSource {
    let frames: [PitchSample]
    private(set) var startCount = 0
    init(_ frames: [PitchSample]) { self.frames = frames }
    func start() async throws -> AsyncStream<PitchSample> {
        startCount += 1
        return AsyncStream { continuation in
            for frame in frames { continuation.yield(frame) }
            continuation.finish()
        }
    }
    func stop() {}
}

nonisolated final class SequenceRangePitchSource: LivePitchSource {
    private(set) var startCount = 0
    func start() async throws -> AsyncStream<PitchSample> {
        let note = [57.0, 57.0, 48.0, 67.0][min(startCount, 3)]
        startCount += 1
        return AsyncStream { continuation in
            for frame in 0...500 {
                continuation.yield(PitchSample(
                    captureTime: CMTime(seconds: Double(frame) * 0.05, preferredTimescale: 60000),
                    frequency: Float(440 * pow(2, (note - 69) / 12)), rmsDecibels: -20))
            }
            continuation.finish()
        }
    }
    func stop() {}
}

nonisolated final class WaitingRangePitchSource: LivePitchSource {
    private(set) var startCount = 0
    private var continuation: AsyncStream<PitchSample>.Continuation?
    func start() async throws -> AsyncStream<PitchSample> {
        startCount += 1
        return AsyncStream { continuation = $0 }
    }
    func stop() { continuation?.finish(); continuation = nil }
}

@main
struct VocalRangeHoldChecks {
    static func sample(_ time: Double, _ midi: Double?, rms: Float = -20) -> PitchSample {
        PitchSample(captureTime: CMTime(seconds: time, preferredTimescale: 60000),
                    frequency: midi.map { Float(440 * pow(2, ($0 - 69) / 12)) }, rmsDecibels: rms)
    }
    /// Runs the warm-up on these frames until it stops listening (capture, failure or end of input).
    @MainActor static func warmUp(_ frames: [PitchSample]) async -> VocalRangeViewModel {
        let model = VocalRangeViewModel(source: RangePitchSource(frames), repository: FakeVocalRangeRepository(),
                                        configuration: .default, onSaved: {})
        model.listen()
        for _ in 0..<10000 {
            if case .listening = model.status { await Task.yield() } else { break }
        }
        return model
    }
    /// Reading aloud, 50 ms frames: a pitched syllable (4), a consonant without pitch (2), a short pause (2).
    static func reading(for seconds: Double) -> [PitchSample] {
        (0..<Int(seconds / 0.05)).map { frame in
            let time = Double(frame) * 0.05
            switch frame % 8 {
            case 0..<4: return sample(time, 52)
            case 4..<6: return sample(time, nil)
            default: return sample(time, nil, rms: -70)
            }
        }
    }
    static func require(_ value: Bool, _ message: String) {
        precondition(value, message)
    }
    @MainActor static func main() async {
        let duration = AppConfiguration.default.vocalRangeHoldDuration
        require(duration == 1, "A sung note requires a one-second hold")
        var detector = DetectVocalRangeUseCase(duration: duration)
        for frame in 0..<20 {
            require(detector.ingest(sample(Double(frame) * 0.05, 48)) == nil,
                    "A note cannot pass before one second")
        }
        require(detector.ingest(sample(1, 48)).map { abs($0 - 48) < 0.01 } == true,
                "One second captures the measured note")
        var interrupted = DetectVocalRangeUseCase(duration: duration)
        for frame in 0..<10 { interrupted.ingest(sample(Double(frame) * 0.05, 48)) }
        interrupted.ingest(sample(0.8, nil))
        require(interrupted.stableDuration == 0, "Silence resets the hold")
        for frame in 0..<20 {
            require(interrupted.ingest(sample(0.9 + Double(frame) * 0.05, 48)) == nil,
                    "An interrupted hold must start again")
        }
        var changedPitch = DetectVocalRangeUseCase(duration: duration)
        for frame in 0..<10 { changedPitch.ingest(sample(Double(frame) * 0.05, 48)) }
        changedPitch.ingest(sample(0.5, 55))
        require(changedPitch.stableDuration == 0, "Changing pitch resets progress")
        var glide = DetectVocalRangeUseCase(duration: duration)
        for frame in 0..<100 {
            require(glide.ingest(sample(Double(frame) * 0.05, 48 + Double(frame) * 0.1)) == nil,
                    "Sliding across notes must not pass")
        }
        let mapping = LivePitchPositionUseCase()
        require(mapping.execute(midi: nil) == nil, "Silence has no live pitch position")
        require(mapping.execute(midi: .nan) == nil, "Non-finite pitch is rejected")
        require(mapping.execute(midi: 140) == nil, "Invalid MIDI is rejected")
        require(mapping.execute(frequency: 440)?.nearestNote == 69, "440 Hz centers the ordered scale at A4")
        for frequency in [Double(0), -1, .infinity, .nan] {
            require(mapping.execute(frequency: frequency) == nil, "Invalid frequencies do not move the scale")
        }
        // The note label and slider marker share a snapped anchor even when a singer is slightly sharp/flat.
        for midi: Float in [47.51, 47.9, 48, 48.1, 48.49] {
            let position = mapping.execute(midi: midi)!
            require(position.nearestNote == 48 && position.noteMIDI == 48,
                    "C3 marker is exactly aligned with the C3 tick for every C3-labelled input")
            require(position.midi == Double(midi), "Visual snapping preserves measured pitch for analysis")
        }
        for note in 1...126 {
            for detune: Float in [-0.49, 0, 0.49] {
                let position = mapping.execute(midi: Float(note) + detune)!
                require(position.noteMIDI == Double(note), "Each note label has the same exact slider anchor")
            }
        }
        require(mapping.execute(midi: 48.51)?.noteMIDI == 49,
                "Crossing the semitone midpoint advances the scale to C sharp 3")
        let exact = mapping.execute(midi: 60)!
        let quarter = mapping.execute(midi: 60.25)!
        let next = mapping.execute(midi: 61)!
        require(exact.offset(of: 59) == -1 && exact.offset(of: 60) == 0 && exact.offset(of: 61) == 1,
                "Adjacent labels remain consecutive chromatic semitones")
        require(quarter.nearestNote == 60 && abs(quarter.centsFromNote - 25) < 0.01,
                "Sub-semitone input retains the measured tuning offset")
        require(next.nearestNote == 61 && next.offset(of: 60) == -1 && next.offset(of: 62) == 1,
                "Increasing microphone pitch moves the previous note left and the next note into the center")
        require(mapping.execute(midi: 0)?.nearestNote == 0 && mapping.execute(midi: 127)?.nearestNote == 127,
                "The scale covers the full MIDI range without the old viewport clamp")
        let source = RangePitchSource((0...500).map { sample(Double($0) * 0.05, 57) })
        let model = VocalRangeViewModel(source: source, repository: FakeVocalRangeRepository(),
                                        configuration: .default, onSaved: {})
        require(source.startCount == 0 && !model.hasStartedListening, "Opening a test must not start the microphone")
        model.next()
        require(model.prompt == .speaking, "Continue is blocked before capture")
        model.toggleMicrophone()
        require(model.hasStartedListening, "Tapping the mic switches the icon to a waveform")
        for _ in 0..<10000 {
            if case .listening = model.status { await Task.yield() } else { break }
        }
        require(model.baselineMIDI.map { abs($0 - 57) < 0.01 } == true, "Speech captures its actual median")
        require(model.readingDuration > AppConfiguration.default.speakingSampleDuration,
                "Warm-up duration is derived from the actual paragraph length")
        require(model.waveformLevels.count <= 25 && model.waveformLevels.contains { $0 > 0 },
                "Waveform amplitude comes from microphone RMS frames")
        model.next()
        require(model.prompt == .lowest && model.status == .idle, "Warm-up advances after capture")
        require(source.startCount == 1 && !model.hasStartedListening,
                "Advancing leaves the next prompt idle until its microphone is tapped")
        model.toggleMicrophone(practice: true)
        for _ in 0..<10000 {
            if case .listening = model.status { await Task.yield() } else { break }
        }
        require(model.hasPracticedHumming && model.lowestMIDI == nil && model.holdProgress == 1,
                "Humming practice requires a stable hold without saving it as the lowest note")
        model.resetCapture()
        require(model.status == .idle && !model.hasStartedListening && model.holdProgress == 0,
                "The next screen starts with an idle microphone")
        model.toggleMicrophone()
        for _ in 0..<10000 {
            if case .listening = model.status { await Task.yield() } else { break }
        }
        require(model.lowestMIDI != nil, "An explicit tap captures the actual low note")
        model.restart()
        require(model.holdProgress == 0 && model.liveMIDI == nil && model.baselineMIDI == nil,
                "Restart clears progress and notes")
        let silence = await warmUp((0...500).map { sample(Double($0) * 0.05, nil, rms: -70) })
        require(silence.holdProgress == 0 && silence.baselineMIDI == nil,
                "Silence must not move passage progress or capture a baseline")
        // Warm-up progress follows reading time, not just the pitched part of speech.
        let readingTime = model.readingDuration
        let tooShort = await warmUp(reading(for: readingTime * 0.9))
        require(tooShort.baselineMIDI == nil && tooShort.holdProgress > 0.85,
                "Reading with consonants and short pauses moves progress at reading pace (\(tooShort.holdProgress))")
        let enough = await warmUp(reading(for: readingTime * 1.05))
        require(enough.baselineMIDI.map { abs($0 - 52) < 0.01 } == true,
                "Reading the passage at a normal pace finishes the warm-up and keeps the spoken note")
        let paused = await warmUp((0..<60).map { sample(Double($0) * 0.05, 52) }
            + (60..<120).map { sample(Double($0) * 0.05, nil, rms: -70) })
        let pausedSeconds = paused.holdProgress * model.readingDuration
        require(pausedSeconds > 2.9 && pausedSeconds < 3.6,
                "A long silence stops progress after the pause tolerance (\(pausedSeconds) s)")
        let unpitched = await warmUp(reading(for: readingTime * 1.05).map { sample($0.captureTime.seconds, nil, rms: $0.rmsDecibels) })
        require(unpitched.baselineMIDI == nil, "Speech without any detected pitch cannot finish the warm-up")
        let waiting = WaitingRangePitchSource()
        let stopped = VocalRangeViewModel(source: waiting, repository: FakeVocalRangeRepository(),
                                           configuration: .default, onSaved: {})
        stopped.toggleMicrophone()
        for _ in 0..<10000 { if waiting.startCount > 0 { break }; await Task.yield() }
        require(waiting.startCount == 1 && stopped.status == .listening,
                "One microphone tap starts exactly one input stream")
        stopped.toggleMicrophone()
        for _ in 0..<20 { await Task.yield() }
        require(stopped.status == .idle && !stopped.hasStartedListening && stopped.holdProgress == 0,
                "Tapping again stops input without a stale capture error")
        let sequence = SequenceRangePitchSource()
        let store = FakeVocalRangeRepository()
        let complete = VocalRangeViewModel(source: sequence, repository: store, configuration: .default, onSaved: {})
        for phase in 0..<4 {
            complete.toggleMicrophone(practice: phase == 1)
            for _ in 0..<10000 {
                if case .listening = complete.status { await Task.yield() } else { break }
            }
            if phase == 0 || phase == 2 { complete.next() }
            if phase == 1 { complete.resetCapture() }
        }
        complete.save()
        require(sequence.startCount == 4 && store.load() == VocalRange(lowestMIDI: 48, highestMIDI: 67),
                "Four explicit taps measure speech, practice, low and high, then persist the actual range")
        print("PASS: one-second hold, tap-to-start, waveform state, humming practice, silence, pitch changes, baseline, restart, warm-up reading pace")
    }
}
