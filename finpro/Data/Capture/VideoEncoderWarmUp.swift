//
//  VideoEncoderWarmUp.swift
//  finpro
//
//  The first AVAssetWriter.startWriting() after an install took 14 s on an iPhone (the system
//  sets up its video encoders once); later ones take a few ms. Done during a recording, it held
//  the capture queue: the preview stuttered and the first frame came far too late. This starts
//  one throwaway HEVC writer when the app opens, so the recording never pays for it.
//

import AVFoundation
import os

nonisolated enum VideoEncoderWarmUp {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "finpro", category: "Capture")
    /// Runs once per launch, on first use of `start()` or `wait()`.
    private static let warmUp = Task.detached(priority: .utility) { run() }

    /// Starts the warm-up in the background (app launch).
    static func start() { _ = warmUp }

    /// Waits until the encoder is ready (camera prepare), starting it if needed.
    static func wait() async { await warmUp.value }

    private static func run() {
        let started = ContinuousClock.now
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("EncoderWarmUp-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: url) }
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return }
        // Same encoder as the recording (CaptureRepositoryImpl.makeVideoInput, portrait 1080×1920).
        let input = CaptureRepositoryImpl.makeVideoInput(width: 1080, height: 1920)
        guard writer.canAdd(input) else { return }
        writer.add(input)
        let ready = writer.startWriting()
        writer.cancelWriting()
        log.notice("video encoder warm-up \(ready ? "done" : "failed", privacy: .public) in \((ContinuousClock.now - started).formatted(.units(allowed: [.seconds, .milliseconds])), privacy: .public)")
    }
}
