//
//  VideoCompositionRepositoryImpl.swift
//  finpro
//
//  Stitches passed takes, mixes in the instrumental and exports FinalCoverVideo.mp4 (PRD §5.9).
//  Owner: Zildjian Vito (ZV-10).
//

import AVFoundation
import CoreMedia
import os

nonisolated final class VideoCompositionRepositoryImpl: VideoCompositionRepository {
    let outputURL: URL
    /// 1920×1080 caps a portrait recording at 1080×1920 and encodes H.264 + AAC.
    let presetName: String

    /// Waits before each retry of an interrupted export. Right after a recording, iOS can still be
    /// releasing the video encoder and decoder it used, and stops the export at once
    /// (AVError.operationInterrupted, -11847); a moment later it goes through.
    static let interruptedRetryDelays: [Duration] = [.milliseconds(500), .milliseconds(1500)]
    /// AVErrorOperationInterrupted (not exposed as an `AVError.Code` case in Swift).
    static let operationInterruptedCode = -11847

    static func isInterruption(_ error: NSError) -> Bool {
        error.domain == AVFoundationErrorDomain && error.code == operationInterruptedCode
    }

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "finpro", category: "Export")

    init(outputURL: URL = SessionFiles.finalVideoURL,
         presetName: String = AVAssetExportPreset1920x1080) {
        self.outputURL = outputURL
        self.presetName = presetName
    }

    func stitchAndExport(plan: CompingCompositionPlan,
                         progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let violations = plan.validate()
        guard violations.isEmpty else { throw CompingError.invalidPlan(violations) }

        let output = try await CompingCompositionBuilder().build(plan)
        let url = outputURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        var delays = Self.interruptedRetryDelays[...]
        while true {
            do {
                try await export(output, plan: plan, to: url, progress: progress)
                break
            } catch let error as NSError where Self.isInterruption(error) {
                guard let delay = delays.popFirst() else {
                    Self.log.error("export interrupted, no retries left: \(error.localizedDescription, privacy: .public)")
                    throw CompingError.exportInterrupted
                }
                Self.log.notice("export interrupted, retrying in \(delay.formatted(), privacy: .public)")
                progress(0)
                try await Task.sleep(for: delay)
            }
        }
        progress(1)
        return url
    }

    /// One export attempt with a new session (a session that failed cannot be restarted).
    private func export(_ output: CompingCompositionBuilder.Output, plan: CompingCompositionPlan, to url: URL,
                        progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let session = AVAssetExportSession(asset: output.composition, presetName: presetName) else {
            throw CompingError.exportUnavailable
        }
        session.audioMix = output.audioMix
        session.videoComposition = output.videoComposition
        session.timeRange = CMTimeRange(start: .zero,
                                        end: CMTime(seconds: plan.endTime, preferredTimescale: CompingCompositionBuilder.timescale))
        try? FileManager.default.removeItem(at: url)

        let progressTask = Task {
            for await state in session.states(updateInterval: 0.1) {
                if case .exporting(let exportProgress) = state {
                    progress(exportProgress.fractionCompleted)
                }
            }
        }
        defer { progressTask.cancel() }
        try await session.export(to: url, as: .mp4)
    }
}
