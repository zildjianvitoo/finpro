//
//  FakeReferencePlaybackRepository.swift
//  finpro
//
//  Fake for local development and previews. Owner: Zildjian Vito (ZV-03).
//  Swap for the real implementation in AppContainer when it lands.
//

#if DEBUG
import AVFoundation
import CoreMedia
import Foundation

/// Plays the loaded song (and the end of the lead-in before 0) through the speaker, starting
/// `latency` seconds from now on the host clock (the same clock FakeCaptureRepository uses), and
/// reports that moment as when it is heard. Without a loaded song, or when audio can't start, it
/// stays silent and only reports the time, so the recording loop still runs.
nonisolated final class FakeReferencePlaybackRepository: ReferencePlaybackRepository, @unchecked Sendable {
    let latency: TimeInterval
    /// Called with (referenceTime, heard capture time) on every play, e.g. by SimulatedSinger.
    let onPlay: (@Sendable (TimeInterval, CMTime) -> Void)?
    /// Guards the engine and the loaded files; `play` and `stop` come from the main actor and tasks.
    private let lock = NSLock()
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var file: AVAudioFile?
    private var leadInFile: AVAudioFile?

    init(latency: TimeInterval = 0, onPlay: (@Sendable (TimeInterval, CMTime) -> Void)? = nil) {
        self.latency = latency
        self.onPlay = onPlay
    }

    func load(earphoneMixURL: URL) throws {
        lock.withLock {
            node.stop()
            leadInFile = nil
            file = try? AVAudioFile(forReading: earphoneMixURL)
            guard let file else { return }
            if engine.attachedNodes.contains(node) { engine.disconnectNodeOutput(node) } else { engine.attach(node) }
            engine.connect(node, to: engine.mainMixerNode, format: file.processingFormat)
        }
    }

    func loadLeadIn(mixURL: URL?, instrumentalURL: URL?) throws {
        lock.withLock {
            leadInFile = nil
            // Queued on the same node right before the song, so it needs the song's format.
            guard let mixURL, let file, let leadIn = try? AVAudioFile(forReading: mixURL),
                  leadIn.processingFormat == file.processingFormat, leadIn.length > 0 else { return }
            leadInFile = leadIn
        }
    }

    func play(from referenceTime: TimeInterval) throws -> CMTime {
        let heard = CMClockGetTime(CMClockGetHostTimeClock()) + CMTime(seconds: latency, preferredTimescale: 600)
        lock.withLock { schedule(from: referenceTime, songAt: heard) }
        onPlay?(referenceTime, heard)
        return heard
    }

    func stop() {
        lock.withLock {
            node.stop()
            engine.stop()
        }
    }

    /// As the device does: the end of the lead-in before 0, the song from 0 at `songAt`.
    private func schedule(from referenceTime: TimeInterval, songAt heard: CMTime) {
        guard let file else { return }
        let rate = file.processingFormat.sampleRate
        let start = AVAudioFramePosition((max(0, referenceTime) * rate).rounded())
        guard start < file.length else { return }
        node.stop()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            if !engine.isRunning { try engine.start() }
        } catch { return }
        let beforeZero = max(0, -referenceTime)
        var leadSeconds = 0.0
        if beforeZero > 0, let leadInFile {
            let frames = min(leadInFile.length, AVAudioFramePosition((beforeZero * rate).rounded()))
            node.scheduleSegment(leadInFile, startingFrame: leadInFile.length - frames,
                                 frameCount: AVAudioFrameCount(frames), at: nil)
            leadSeconds = Double(frames) / rate
        }
        node.scheduleSegment(file, startingFrame: start, frameCount: AVAudioFrameCount(file.length - start), at: nil)
        // `heard` is the reference time itself; the song's 0 comes `beforeZero` later, and the
        // node starts where its first queued segment (the lead-in tail, or the song) starts.
        let songPlays = heard.seconds + beforeZero
        node.play(at: AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: songPlays - leadSeconds)))
    }
}

#endif
