//
//  AudioPreviewPlayer.swift
//  finpro
//
//  Plays one file (or a rendered excerpt) through the speaker or earphones for the trim,
//  key choice and Ready screen previews.
//

import AVFoundation
import os

nonisolated final class AudioPreviewPlayer: NSObject, AudioPreviewing, AVAudioPlayerDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "audio.preview", qos: .userInitiated)
    private let lock = NSLock()
    private var player: AVAudioPlayer?
    private var excerptURL: URL?
    private var completion: (@Sendable () -> Void)?
    private var pendingStartTime: TimeInterval?
    private var generation = UUID()
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "finpro", category: "Preview")

    func play(_ url: URL, from start: TimeInterval) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        stop()
        let token = lock.withLock { () -> UUID in
            pendingStartTime = start
            return generation
        }
        queue.async { [self] in
            guard lock.withLock({ generation == token }) else { return }
            do {
                try Self.activatePlaybackSession()
                let player = try AVAudioPlayer(contentsOf: url)
                player.currentTime = start
                player.prepareToPlay()
                lock.withLock {
                    guard generation == token else { return }
                    guard player.play() else {
                        Self.log.error("preview player.play() returned false for \(url.lastPathComponent, privacy: .public)")
                        pendingStartTime = nil
                        return
                    }
                    self.player = player
                    self.pendingStartTime = nil
                }
            } catch {
                lock.withLock {
                    if generation == token { pendingStartTime = nil }
                }
                Self.log.error("preview play failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func play(_ url: URL, excerpt: ClosedRange<TimeInterval>,
              onCompletion: @escaping @Sendable () -> Void) async throws {
        stop()
        let token = lock.withLock { generation }
        let render = Task.detached(priority: .userInitiated) {
            try AudioExcerptRenderer().render(url, excerpt: excerpt)
        }
        let clip = try await withTaskCancellationHandler {
            try await render.value
        } onCancel: { render.cancel() }
        do {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                queue.async { [self] in
                    do {
                        guard lock.withLock({ generation == token }) else { throw CancellationError() }
                        try Self.activatePlaybackSession()
                        let player = try AVAudioPlayer(contentsOf: clip)
                        player.delegate = self
                        try lock.withLock {
                            guard generation == token else { throw CancellationError() }
                            guard player.play() else { throw CocoaError(.fileReadUnknown) }
                            self.player = player
                            excerptURL = clip
                            completion = onCompletion
                        }
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            Self.log.notice("playing \(url.lastPathComponent, privacy: .public) \(excerpt.lowerBound, privacy: .public)-\(excerpt.upperBound, privacy: .public)")
        } catch {
            try? FileManager.default.removeItem(at: clip)
            throw error
        }
    }

    var currentTime: TimeInterval? {
        lock.withLock {
            if let player { return player.isPlaying ? player.currentTime : nil }
            return pendingStartTime
        }
    }

    func stop() {
        let stopped = lock.withLock { () -> (AVAudioPlayer?, URL?) in
            generation = UUID()
            pendingStartTime = nil
            if player != nil { Self.log.notice("stopped") }
            defer { player = nil; excerptURL = nil; completion = nil }
            return (player, excerptURL)
        }
        stopped.0?.stop()
        if let url = stopped.1 { try? FileManager.default.removeItem(at: url) }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        finish(player)
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        finish(player)
    }

    private static func activatePlaybackSession() throws {
        let session = AVAudioSession.sharedInstance()
        // Clear any headset input/sample-rate pin left by a prior recording or vocal-range session.
        try? session.setPreferredInput(nil)
        try? session.setPreferredSampleRate(0)
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            // Brief retry if a prior capture/Bluetooth audio session is still tearing down.
            Thread.sleep(forTimeInterval: 0.12)
            try? session.setPreferredInput(nil)
            try? session.setPreferredSampleRate(0)
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        }
    }

    private func finish(_ finishedPlayer: AVAudioPlayer) {
        let finished = lock.withLock { () -> (URL?, (@Sendable () -> Void)?) in
            guard player === finishedPlayer else { return (nil, nil) }
            defer { player = nil; excerptURL = nil; completion = nil }
            return (excerptURL, completion)
        }
        if let url = finished.0 { try? FileManager.default.removeItem(at: url) }
        finished.1?()
    }
}
