//
//  CameraLook.swift
//  finpro
//
//  The camera's exposure, white balance and focus at the start of a cover's first recording. Later
//  passes (retake, continue) apply it again, so their clips match in brightness, colour and sharpness.
//

import AVFoundation

nonisolated struct CameraLook {
    let exposureDuration: CMTime
    let iso: Float
    let whiteBalanceGains: AVCaptureDevice.WhiteBalanceGains
    let lensPosition: Float

    /// Locks the camera as it is now (auto exposure and white balance have settled during the preview)
    /// and returns what it locked. Call with the device locked for configuration.
    static func lockCurrent(on device: AVCaptureDevice) -> CameraLook {
        if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
        if device.isWhiteBalanceModeSupported(.locked) { device.whiteBalanceMode = .locked }
        if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
        return CameraLook(exposureDuration: device.exposureDuration, iso: device.iso,
                          whiteBalanceGains: device.deviceWhiteBalanceGains, lensPosition: device.lensPosition)
    }

    /// Sets the device to this look, within what its current format allows. Call with the device
    /// locked for configuration.
    func apply(to device: AVCaptureDevice) {
        let format = device.activeFormat
        if device.isExposureModeSupported(.custom) {
            // An exposure can't be longer than a frame.
            let longest = CMTimeMinimum(format.maxExposureDuration, device.activeVideoMaxFrameDuration)
            let duration = CMTimeMaximum(format.minExposureDuration, CMTimeMinimum(exposureDuration, longest))
            device.setExposureModeCustom(duration: duration, iso: min(max(iso, format.minISO), format.maxISO))
        }
        if device.isWhiteBalanceModeSupported(.locked) {
            let maximum = device.maxWhiteBalanceGain
            func clamp(_ gain: Float) -> Float { min(max(gain, 1), maximum) }
            let gains = AVCaptureDevice.WhiteBalanceGains(redGain: clamp(whiteBalanceGains.redGain),
                                                          greenGain: clamp(whiteBalanceGains.greenGain),
                                                          blueGain: clamp(whiteBalanceGains.blueGain))
            device.setWhiteBalanceModeLocked(with: gains)
        }
        if device.isLockingFocusWithCustomLensPositionSupported {
            device.setFocusModeLocked(lensPosition: lensPosition)
        }
    }

    /// Back to automatic between recordings, so the preview follows the light again.
    static func restoreAutomatic(on device: AVCaptureDevice) {
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { device.whiteBalanceMode = .continuousAutoWhiteBalance }
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
    }
}
