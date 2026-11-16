//
//  KeepScreenAwake.swift
//  finpro
//
//  Stops the screen from dimming and locking while the user is not touching it: during a cover
//  recording (the user is singing, not tapping) and during long work that iOS would interrupt
//  when the phone locks (preparing a song, merging the cover). Several screens may ask at once;
//  the screen may sleep again only when none does.
//

import SwiftUI
import UIKit
import os

@MainActor
enum ScreenAwakeRequests {
    private static var count = 0
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "finpro", category: "Screen")

    static func add() {
        count += 1
        if count == 1 { log.notice("screen stays awake") }
        UIApplication.shared.isIdleTimerDisabled = true
    }

    static func remove() {
        count = max(0, count - 1)
        if count == 0 {
            UIApplication.shared.isIdleTimerDisabled = false
            log.notice("screen may sleep again")
        }
    }
}

private struct KeepScreenAwake: ViewModifier {
    let isActive: Bool
    @State private var holds = false

    func body(content: Content) -> some View {
        content
            .onAppear { update(isActive) }
            .onChange(of: isActive) { _, active in update(active) }
            .onDisappear { update(false) }
    }

    private func update(_ active: Bool) {
        guard active != holds else { return }
        holds = active
        if active { ScreenAwakeRequests.add() } else { ScreenAwakeRequests.remove() }
    }
}

extension View {
    /// Keeps the screen on (no dimming or auto-lock) while `isActive` and this view is shown.
    func keepsScreenAwake(_ isActive: Bool = true) -> some View {
        modifier(KeepScreenAwake(isActive: isActive))
    }
}
