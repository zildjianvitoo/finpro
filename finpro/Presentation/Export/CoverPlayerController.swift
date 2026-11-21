//
//  CoverPlayerController.swift
//  finpro
//
//  Plays the exported cover on the result screen (7.1): play/pause, the elapsed time for the seek
//  bar, and jumping to a clip. Owner: Zildjian Vito (ZV-13).
//

import AVFoundation
import Observation

@Observable
final class CoverPlayerController {
    let player: AVPlayer
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    /// The user is dragging the seek bar: the picture follows the finger and playback waits.
    private(set) var isScrubbing = false
    @ObservationIgnored private var resumesAfterScrubbing = false

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    /// Non-observed mirrors read by `liveTime()` at 60/120 Hz so Canvas redraws never register
    /// `@Observable` dependencies on the 10 Hz `currentTime` ticker.
    @ObservationIgnored private var livePlaying = false
    @ObservationIgnored private var liveScrubbing = false
    @ObservationIgnored private var liveFallbackTime: TimeInterval = 0
    @ObservationIgnored private var liveDuration: TimeInterval = 0
    private let refreshInterval = CMTime(value: 1, timescale: 10)

    convenience init(url: URL) { self.init(item: AVPlayerItem(url: url)) }

    init(item: AVPlayerItem) {
        player = AVPlayer(playerItem: item)
        timeObserver = player.addPeriodicTimeObserver(forInterval: refreshInterval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.update(time: time) }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: player.currentItem, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.livePlaying = false
                self?.isPlaying = false
            }
        }
        Task { await loadDuration() }
    }

    isolated deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    /// Elapsed share of the cover, 0...1.
    var progress: Double { duration > 0 ? min(1, currentTime / duration) : 0 }

    /// Continuous playback time for 60/120 Hz animations (pitch guide). Reads the player item's
    /// lock-free `CMTimebase` while playing to avoid `AVPlayer.currentTime()` jitter and locks.
    func liveTime() -> TimeInterval {
        guard livePlaying, !liveScrubbing else { return liveFallbackTime }
        if let timebase = player.currentItem?.timebase {
            let time = CMTimebaseGetTime(timebase)
            if time.isNumeric {
                let seconds = time.seconds
                if seconds.isFinite {
                    return liveDuration > 0 ? min(max(0, seconds), liveDuration) : max(0, seconds)
                }
            }
        }
        let time = player.currentTime()
        if time.isNumeric, time.seconds.isFinite {
            let seconds = time.seconds
            return liveDuration > 0 ? min(max(0, seconds), liveDuration) : max(0, seconds)
        }
        return liveFallbackTime
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    func play() {
        // At the end, play again from the start.
        if duration > 0, currentTime >= duration - 0.05 { seek(to: 0) }
        player.play()
        livePlaying = true
        isPlaying = true
    }

    func pause() {
        player.pause()
        livePlaying = false
        isPlaying = false
    }

    func beginScrubbing() {
        guard !isScrubbing else { return }
        liveScrubbing = true
        isScrubbing = true
        resumesAfterScrubbing = isPlaying
        player.pause()
    }

    /// Moves to a share of the cover (0...1) while dragging. Frames near the spot are fine here, so
    /// the picture keeps up with the finger.
    func scrub(to fraction: Double) {
        guard duration > 0 else { return }
        let target = min(max(fraction, 0), 1) * duration
        liveFallbackTime = target
        currentTime = target
        let tolerance = CMTime(value: 1, timescale: 30)
        player.seek(to: CMTime(seconds: currentTime, preferredTimescale: 600), toleranceBefore: tolerance, toleranceAfter: tolerance)
    }

    /// Lands on the exact frame and plays on if it was playing before the drag.
    func endScrubbing() {
        guard isScrubbing else { return }
        liveScrubbing = false
        isScrubbing = false
        seek(to: currentTime)
        if resumesAfterScrubbing { play() }
    }

    func seek(to time: TimeInterval) {
        let target = duration > 0 ? min(max(time, 0), duration) : max(time, 0)
        liveFallbackTime = target
        currentTime = target
        player.seek(to: CMTime(seconds: currentTime, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func update(time: CMTime) {
        guard time.isNumeric, !isScrubbing else { return }
        liveFallbackTime = time.seconds
        currentTime = time.seconds
    }

    private func loadDuration() async {
        guard let asset = player.currentItem?.asset,
              let value = try? await asset.load(.duration), value.isNumeric else { return }
        liveDuration = value.seconds
        duration = value.seconds
    }
}
