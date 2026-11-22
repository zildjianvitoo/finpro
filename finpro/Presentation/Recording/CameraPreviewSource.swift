//
//  CameraPreviewSource.swift
//  finpro
//
//  Gives the recording screen the live camera session without putting AVCaptureSession
//  into the Domain layer (PRD §6.1). Implemented by CaptureRepositoryImpl.
//

import AVFoundation

nonisolated protocol CameraPreviewSource: AnyObject {
    var previewSession: AVCaptureSession { get }
    /// The camera being previewed, for AVCaptureDevice.RotationCoordinator. nil before setup.
    var previewDevice: AVCaptureDevice? { get }
    /// Starts only the camera preview (no audio session or microphone), so the camera feed stays
    /// visible behind pre-recording alerts such as "Plug in earphones".
    func startPreviewOnly() async
}
