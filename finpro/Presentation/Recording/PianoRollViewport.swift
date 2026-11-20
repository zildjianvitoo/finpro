//
//  PianoRollViewport.swift
//  finpro
//
//  The pitch guide's visible lines, eased toward where the notes are so the rows glide instead
//  of jumping when a note comes into view. Updated while drawing (it does not trigger redraws).
//

import Foundation

final class PianoRollViewport {
    /// Seconds to cover about two thirds of the way to a new position.
    static let easing: TimeInterval = 0.25
    /// A gap longer than this (paused, a dialog) snaps instead of easing.
    static let snapAfter: TimeInterval = 0.5

    private var center: Double?
    private var span: Double?
    private var lastUpdate: TimeInterval = 0

    /// Moves toward the target and returns the lines to draw now.
    func update(center targetCenter: Double, span targetSpan: Double) -> (center: Double, span: Double) {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - lastUpdate
        lastUpdate = now
        guard let center, let span, elapsed < Self.snapAfter else {
            self.center = targetCenter
            self.span = targetSpan
            return (targetCenter, targetSpan)
        }
        let step = 1 - exp(-elapsed / Self.easing)
        let newCenter = center + (targetCenter - center) * step
        let newSpan = span + (targetSpan - span) * step
        self.center = newCenter
        self.span = newSpan
        return (newCenter, newSpan)
    }
}
