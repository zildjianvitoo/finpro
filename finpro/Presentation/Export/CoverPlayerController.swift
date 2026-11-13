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
    private let refreshInterval = CMTime(value: 1, timescale: 10)

    init(url: URL) {
        player = AVPlayer(url: url)
        timeObserver = player.addPeriodicTimeObserver(forInterval: refreshInterval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.update(time: time) }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: player.currentItem, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isPlaying = false }
        }
        Task { await loadDuration() }
    }

    isolated deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    /// Elapsed share of the cover, 0...1.
    var progress: Double { duration > 0 ? min(1, currentTime / duration) : 0 }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    func play() {
        // At the end, play again from the start.
        if duration > 0, currentTime >= duration - 0.05 { seek(to: 0) }
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func beginScrubbing() {
        guard !isScrubbing else { return }
        isScrubbing = true
        resumesAfterScrubbing = isPlaying
        player.pause()
    }

    /// Moves to a share of the cover (0...1) while dragging. Frames near the spot are fine here, so
    /// the picture keeps up with the finger.
    func scrub(to fraction: Double) {
        guard duration > 0 else { return }
        currentTime = min(max(fraction, 0), 1) * duration
        let tolerance = CMTime(value: 1, timescale: 30)
        player.seek(to: CMTime(seconds: currentTime, preferredTimescale: 600), toleranceBefore: tolerance, toleranceAfter: tolerance)
    }

    /// Lands on the exact frame and plays on if it was playing before the drag.
    func endScrubbing() {
        guard isScrubbing else { return }
        isScrubbing = false
        seek(to: currentTime)
        if resumesAfterScrubbing { play() }
    }

    func seek(to time: TimeInterval) {
        currentTime = duration > 0 ? min(max(time, 0), duration) : max(time, 0)
        player.seek(to: CMTime(seconds: currentTime, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func update(time: CMTime) {
        guard time.isNumeric, !isScrubbing else { return }
        currentTime = time.seconds
    }

    private func loadDuration() async {
        guard let asset = player.currentItem?.asset,
              let value = try? await asset.load(.duration), value.isNumeric else { return }
        duration = value.seconds
    }
}
