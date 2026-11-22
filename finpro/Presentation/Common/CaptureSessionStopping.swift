//
//  CaptureSessionStopping.swift
//  finpro
//
//  Stops the camera/audio capture session and releases the recording audio session before
//  returning to screens that play audio previews (Find Your Key, Select Clip, Song List).
//

import Foundation

nonisolated protocol CaptureSessionStopping: AnyObject {
    /// Stops `AVCaptureSession` and deactivates `AVAudioSession` before returning.
    func stopCaptureSession() async
}
