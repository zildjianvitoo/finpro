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
