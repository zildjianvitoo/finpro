//
//  AppChipButtonStyle.swift
//  finpro
//

import SwiftUI

struct AppChipButtonStyle: ButtonStyle {
    var selected = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.appSubheadline)
            .foregroundStyle(selected ? Color.secBrand : Color.primaryBrand)
            .padding(.horizontal, AppSpacing.regular)
            .frame(minHeight: 36)
            .background {
                if selected { Capsule().fill(Color.primaryBrand) }
                else { Capsule().fill(.regularMaterial) }
            }
            .overlay { Capsule().strokeBorder(.white.opacity(0.8), lineWidth: 1) }
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
    }
}
