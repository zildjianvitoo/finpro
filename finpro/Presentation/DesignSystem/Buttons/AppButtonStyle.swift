//
//  AppButtonStyle.swift
//  finpro
//
//  Full-width capsule buttons of the design system (Sketch "Design System" > "Button"):
//  Primary (with its Pressed and Disabled states) and the lime Secondary.
//

import SwiftUI

struct AppButtonStyle: ButtonStyle {
    enum Kind {
        /// Main CTA such as Continue, Save, Start Recording.
        case primary
        /// Lime accent, the "Secondary Button" in Sketch.
        case accent
        case secondary
    }

    var kind: Kind = .primary

    @Environment(\.isEnabled) private var isEnabled

    private let height = AppLayout.buttonHeight

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.appCTA)
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(Capsule().fill(fill(isPressed: configuration.isPressed)))
            .contentShape(Capsule())
    }

    private var textColor: Color {
        guard isEnabled else { return .secText }
        return kind == .primary ? .white : .primary800
    }

    private func fill(isPressed: Bool) -> Color {
        guard isEnabled else { return .secondaryButton }
        switch kind {
        case .primary: return isPressed ? .primary800 : .primaryButton
        case .accent: return isPressed ? .secondary500 : .smallButton
        case .secondary: return isPressed ? .primary100 : .secondaryButton
        }
    }
}

extension ButtonStyle where Self == AppButtonStyle {
    static var appPrimary: AppButtonStyle { AppButtonStyle(kind: .primary) }
    static var appSecondary: AppButtonStyle { AppButtonStyle(kind: .secondary) }
    static var appAccent: AppButtonStyle { AppButtonStyle(kind: .accent) }
}
