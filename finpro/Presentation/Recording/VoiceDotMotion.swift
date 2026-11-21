//
//  VoiceDotMotion.swift
//  finpro
//
//  Glides the lime voice dot to its new height instead of jumping ("tak"): about 0.15 s to get
//  most of the way. Updated while drawing (it does not trigger redraws), like PianoRollViewport.
//

import Foundation

final class VoiceDotMotion {
    /// Time constant of the glide: ~95% of the way after three of these (≈ 0.15 s).
    static let easing: TimeInterval = 0.05
    /// After a longer gap (paused, a dialog) the dot is placed directly.
    static let snapAfter: TimeInterval = 0.5

    private var position: Double?
    private var lastUpdate: TimeInterval = 0

    /// Moves toward `target` (the dot's y on screen) and returns where to draw the dot now.
    func update(target: Double) -> Double {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - lastUpdate
        lastUpdate = now
        guard let position, elapsed < Self.snapAfter else {
            position = target
            return target
        }
        let next = position + (target - position) * (1 - exp(-elapsed / Self.easing))
        self.position = next
        return next
    }
}
