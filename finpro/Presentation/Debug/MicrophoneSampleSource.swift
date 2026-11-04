//
//  MicrophoneSampleSource.swift
//  finpro
//
//  Raw microphone samples on the capture clock, for the click test (sync calibration).
//  Implemented by CaptureRepositoryImpl; not available on the simulator.
//

import Foundation

nonisolated protocol MicrophoneSampleSource: AnyObject {
    func audioChunks() -> AsyncStream<MeasureSyncUseCase.AudioChunk>
}
