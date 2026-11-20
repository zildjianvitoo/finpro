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

    /// Capsule glass button for short text controls such as Skip. Apply to a `Button`.
    @ViewBuilder
    func glassCapsuleButtonStyle() -> some View {
        if #available(iOS 26, *) {
            self.buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
        } else {
            self.buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
        }
    }
}

extension View {
    /// Compact glass capsule for a short text button next to 44 pt icon buttons (Skip in onboarding,
    /// Sketch 59 × 44): the system `.large` glass button is wider and taller than the design.
    /// Apply to a `Button` label's button.
    @ViewBuilder
    func glassPillButtonStyle() -> some View {
        if #available(iOS 26, *) {
            self.buttonStyle(GlassPillStyle())
        } else {
            self.buttonStyle(.bordered).buttonBorderShape(.capsule)
        }
    }
}

@available(iOS 26, *)
private struct GlassPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .frame(minWidth: AppLayout.iconButton, minHeight: AppLayout.iconButton)
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
