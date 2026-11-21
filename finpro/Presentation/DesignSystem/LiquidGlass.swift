//
//  LiquidGlass.swift
//  finpro
//
//  iOS 26+ Liquid Glass button styles with a system bordered fallback on earlier versions.
//

import SwiftUI

extension View {
    /// Round glass button for icon-only controls such as back. Apply to a `Button`.
    @ViewBuilder
    func glassCircleButtonStyle() -> some View {
        if #available(iOS 26, *) {
            self.buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
        } else {
            self.buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.large)
        }
    }
}

extension View {
    /// Compact glass capsule for a short text button next to 44 pt icon buttons (Skip in onboarding,
    /// Sketch 59 × 44): the system `.large` glass button is wider and taller than the design.
    /// Apply to a `Button` label's button. `height` and `horizontalPadding` set a smaller pill
    /// (Select on Song List and Covers; Sketch 3.2 draws it 83 × 36, the app uses 40 for an easier tap).
    @ViewBuilder
    func glassPillButtonStyle(height: CGFloat = AppLayout.iconButton, horizontalPadding: CGFloat = 14) -> some View {
        if #available(iOS 26, *) {
            self.buttonStyle(GlassPillStyle(height: height, horizontalPadding: horizontalPadding))
        } else {
            self.buttonStyle(.bordered).buttonBorderShape(.capsule)
        }
    }
}

@available(iOS 26, *)
private struct GlassPillStyle: ButtonStyle {
    let height: CGFloat
    let horizontalPadding: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, horizontalPadding)
            .frame(minWidth: height, minHeight: height)
            .contentShape(Capsule())
            .glassEffect(.regular.interactive(), in: Capsule())
    }
}

extension View {
    /// Glass panel behind a card such as the recording tips, with a material fallback.
    @ViewBuilder
    func glassCardBackground(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
        }
    }
}

struct LiquidGlassGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer {
                content
            }
        } else {
            content
        }
    }
}
