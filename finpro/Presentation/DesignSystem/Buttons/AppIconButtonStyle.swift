//
//  AppIconButtonStyle.swift
//  finpro
//
//  44 pt round icon buttons of the design system (Sketch "Design System" > "Icon Primary",
//  "Icon Secondary", "Icon Tinted").
//

import SwiftUI

struct AppIconButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
        case tinted
    }

    var kind: Kind = .primary

    @Environment(\.isEnabled) private var isEnabled

    private let size: CGFloat = 44

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.appTitle2.weight(.regular))
            .foregroundStyle(glyph)
            .frame(width: size, height: size)
            .background(Circle().fill(fill))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .contentShape(Circle())
    }

    private var fill: Color {
        switch kind {
        case .primary: .primaryButton
        case .secondary: .smallButton
        case .tinted: .secondaryButton
        }
    }

    private var glyph: Color {
        switch kind {
        case .primary: .white
        case .secondary: .primary800
        case .tinted: .primaryBrand
        }
    }
}

extension ButtonStyle where Self == AppIconButtonStyle {
    static func appIcon(_ kind: AppIconButtonStyle.Kind = .primary) -> AppIconButtonStyle {
        AppIconButtonStyle(kind: kind)
    }
}
