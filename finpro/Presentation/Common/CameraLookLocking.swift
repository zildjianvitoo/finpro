//
//  CameraLookLocking.swift
//  finpro
//

import Foundation

/// Keeps the camera's exposure, white balance and focus the same in every recording pass of a
/// cover, so a retaken clip matches the clips around it. A capture repository adopts it when it can.
nonisolated protocol CameraLookLocking: AnyObject {
    /// A new cover starts: the next recording locks the camera as it is then.
    func resetCameraLook()
}
