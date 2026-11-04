//
//  PrimaryButtonStyle.swift
//  finpro
//
//  Full-width plum capsule used for the main action at the bottom of a screen.
//

import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    /// Shows the white dot used on actions that start listening.
    var showsDot = false

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            if showsDot {
                Circle()
                    .fill(.white)
                    .frame(width: 14, height: 14)
            }
            configuration.label
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(Capsule().fill(Color.brandPlum))
        .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
        .contentShape(Capsule())
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
    static var primaryWithDot: PrimaryButtonStyle { PrimaryButtonStyle(showsDot: true) }
}
