//
//  ReferencePlaybackRepositoryImpl.swift
//  finpro
//
//  Earphone reference playback scheduled on host time and mapped to the capture clock (PRD §7.1).
//

import AVFoundation

/// Serial access from the session controller. Audio scheduling uses host time, not the UI timer.
nonisolated final class ReferencePlaybackRepositoryImpl: ReferencePlaybackRepository, ReferenceVocalPlayback {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let instrumentalNode = AVAudioPlayerNode()
    private var instrumentalFile: AVAudioFile?
    private var referenceVocalEnabled = true
    private let capture: CaptureRepositoryImpl
    private let configuration: () -> AppConfiguration
    private var file: AVAudioFile?
    /// The song before the trimmed part, heard before 0 (`loadLeadIn`).
    private var leadInFile: AVAudioFile?
    private var leadInInstrumentalFile: AVAudioFile?
    /// Playback starts this far in the future so `play(at:)` is scheduled, never late.
    private static let schedulingLead: TimeInterval = 0.1

    /// `configuration` is read on every play so Debug Settings changes (manual latency) apply at once.
    init(capture: CaptureRepositoryImpl, configuration: @escaping () -> AppConfiguration) {
        self.capture = capture
        self.configuration = configuration
        engine.attach(node)
        engine.attach(instrumentalNode)
    }

    func load(earphoneMixURL: URL) throws {
        node.stop(); instrumentalNode.stop()
        engine.stop()
        instrumentalFile = nil
        leadInFile = nil
        leadInInstrumentalFile = nil
        let file = try AVAudioFile(forReading: earphoneMixURL)
        self.file = file
        engine.disconnectNodeOutput(node)
        engine.connect(node, to: engine.mainMixerNode, format: file.processingFormat)
        engine.prepare()
        try engine.start()
    }

    func loadKaraoke(mixURL: URL, instrumentalURL: URL) throws {
        try load(earphoneMixURL: mixURL)
        do {
            let backing = try AVAudioFile(forReading: instrumentalURL)
            guard let file,
                  abs(Double(file.length) / file.processingFormat.sampleRate
                      - Double(backing.length) / backing.processingFormat.sampleRate) <= ContractTolerance.timeline else {
                throw failure("Reference and instrumental durations must match.")
            }
            engine.stop()
            engine.disconnectNodeOutput(instrumentalNode)
            engine.connect(instrumentalNode, to: engine.mainMixerNode, format: backing.processingFormat)
            instrumentalFile = backing
            setReferenceVocalEnabled(referenceVocalEnabled)
            engine.prepare(); try engine.start()
        } catch {
            shutdown(); throw error
        }
    }

    func loadLeadIn(mixURL: URL?, instrumentalURL: URL?) throws {
        leadInFile = nil
        leadInInstrumentalFile = nil
        guard let mixURL, let file else { return }
        // Queued on the same node right before the song, so it must have the song's format.
        let leadIn = try AVAudioFile(forReading: mixURL)
        guard leadIn.processingFormat == file.processingFormat, leadIn.length > 0 else { return }
        leadInFile = leadIn
        if let instrumentalURL, let backing = instrumentalFile,
           let leadInBacking = try? AVAudioFile(forReading: instrumentalURL),
           leadInBacking.processingFormat == backing.processingFormat, leadInBacking.length > 0 {
            leadInInstrumentalFile = leadInBacking
        }
    }

    func setReferenceVocalEnabled(_ enabled: Bool) {
        referenceVocalEnabled = enabled
        node.volume = enabled ? 1 : 0
        instrumentalNode.volume = enabled ? 0 : 1
    }

    func play(from referenceTime: TimeInterval) throws -> CMTime {
        guard let file, referenceTime.isFinite else { throw failure("Invalid reference playback time.") }
        let songStart = max(0, referenceTime)
        let start = AVAudioFramePosition((songStart * file.processingFormat.sampleRate).rounded())
        guard start < file.length else { throw failure("Playback starts outside the song.") }
        // Before 0: the end of the lead-in (the song before the trimmed part), and silence before
        // it where the lead-in is shorter. `referenceTime` is still what is returned.
        let beforeZero = max(0, -referenceTime)
        let leadIn = beforeZero > 0 ? leadInFile.map { Self.tail($0, seconds: beforeZero) } : nil
        let leadInInstrumental = beforeZero > 0 && instrumentalFile != nil
            ? leadInInstrumentalFile.map { Self.tail($0, seconds: beforeZero) } : nil
        node.stop(); instrumentalNode.stop()
        if !engine.isRunning { try engine.start() }
        if let leadIn {
            node.scheduleSegment(leadIn.file, startingFrame: leadIn.from, frameCount: leadIn.frames, at: nil)
        }
        node.scheduleSegment(file, startingFrame: start, frameCount: AVAudioFrameCount(file.length - start), at: nil)
        if let backing = instrumentalFile {
            let backingStart = AVAudioFramePosition((songStart * backing.processingFormat.sampleRate).rounded())
            guard backingStart < backing.length else { throw failure("Instrumental playback starts outside the song.") }
            if let leadInInstrumental {
                instrumentalNode.scheduleSegment(leadInInstrumental.file, startingFrame: leadInInstrumental.from,
                                                 frameCount: leadInInstrumental.frames, at: nil)
            }
            instrumentalNode.scheduleSegment(backing, startingFrame: backingStart,
                                             frameCount: AVAudioFrameCount(backing.length - backingStart), at: nil)
        }
        let host = CMClockGetTime(CMClockGetHostTimeClock())
        let scheduled = CMTimeAdd(host, CMTime(seconds: Self.schedulingLead, preferredTimescale: 60000))
        let songPlays = CMTimeAdd(scheduled, CMTime(seconds: beforeZero, preferredTimescale: 60000))
        // Each node starts where its first queued segment starts: the lead-in, or the song at 0.
        let nodeStarts = CMTimeSubtract(songPlays, CMTime(seconds: leadIn?.seconds ?? 0, preferredTimescale: 60000))
        node.play(at: AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: nodeStarts.seconds)))
        if instrumentalFile != nil {
            let backingStarts = CMTimeSubtract(songPlays, CMTime(seconds: leadInInstrumental?.seconds ?? 0, preferredTimescale: 60000))
            instrumentalNode.play(at: AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: backingStarts.seconds)))
        }
        let session = AVAudioSession.sharedInstance()
        let latency = session.outputLatency + session.ioBufferDuration + configuration().manualLatencyCalibration
        return CMTimeAdd(capture.captureTime(forHostTime: scheduled), CMTime(seconds: latency, preferredTimescale: 60000))
    }

    /// The last `seconds` of `file` (all of it when shorter), as frames to schedule.
    private static func tail(_ file: AVAudioFile, seconds: TimeInterval)
        -> (file: AVAudioFile, from: AVAudioFramePosition, frames: AVAudioFrameCount, seconds: TimeInterval) {
        let rate = file.processingFormat.sampleRate
        let frames = min(file.length, AVAudioFramePosition((seconds * rate).rounded()))
        return (file, file.length - frames, AVAudioFrameCount(frames), Double(frames) / rate)
    }

    /// Also stops the engine so the audio session can be released; `play` restarts it.
    func stop() { node.stop(); instrumentalNode.stop(); engine.stop() }
    func shutdown() { node.stop(); instrumentalNode.stop(); engine.stop() }
    private func failure(_ message: String) -> NSError {
        NSError(domain: "Playback", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
