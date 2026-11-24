//
//  LivePitchSource.swift
//  finpro
//
//  Microphone pitch without the camera, for the vocal range test (PRD §5.1).
//  Implemented by MicrophonePitchSource (device) and FakeLivePitchSource (simulator).
//

import Foundation

nonisolated protocol LivePitchSource: AnyObject {
    /// Starts the microphone. Returns a new stream; it ends when `stop()` is called.
    func start() async throws -> AsyncStream<PitchSample>
    /// Level-only samples for the warm-up waveform.
    func startLevelMonitoring() async throws -> AsyncStream<PitchSample>
    func stop()
}


extension LivePitchSource {
    func startLevelMonitoring() async throws -> AsyncStream<PitchSample> { try await start() }
}
