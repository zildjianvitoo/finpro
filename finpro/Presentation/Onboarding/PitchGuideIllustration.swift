//
//  PitchGuideIllustration.swift
//  finpro
//
//  Onboarding page 1 illustration ("Stay on pitch"), animated from its layers
//  (docs/illustrations/ob1-*): the blob breathes, the ribbon drifts, the notes float, the mascot
//  sways as it sings over its shadow, and the pitch guide card plays natively.
//  Moves only while the page is shown and never with Reduce Motion.
//

import SwiftUI

struct PitchGuideIllustration: View {
    /// The page is on screen.
    var isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Illustration canvas in pixels (all layers share it).
    private static let canvas = CGSize(width: 1063, height: 1189)
    /// Centre of the card and its tilt, measured on ob1-full.
    private static let cardCentre = CGPoint(x: 665.5, y: 434.5)
    private static let cardTilt = Angle.degrees(5)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isActive || reduceMotion)) { context in
            let t = (isActive && !reduceMotion) ? context.date.timeIntervalSinceReferenceDate : 0
            GeometryReader { proxy in
                let unit = proxy.size.width / Self.canvas.width
                let bob = abs(wave(t, period: 1.6))
                ZStack {
                    layer("ob1-blob")
                        .scaleEffect(1 + wave(t, period: 3.2) * 0.025)
                    layer("ob1-ribbon")
                        .offset(x: wave(t, period: 4.0) * 18 * unit)
                    PitchGuideIllustrationCard(time: t, unit: unit)
                        .rotationEffect(Self.cardTilt)
                        .position(x: Self.cardCentre.x * unit, y: Self.cardCentre.y * unit)
                        .offset(y: wave(t, period: 2.8, phase: 0.2) * 8 * unit)
                    layer("ob1-notes")
                        .offset(y: wave(t, period: 2.4, phase: 0.5) * 10 * unit)
                    layer("ob1-shadow")
                        .scaleEffect(1 - bob * 0.06, anchor: UnitPoint(x: 0.3, y: 0.92))
                    layer("ob1-mascot")
                        .rotationEffect(.degrees(wave(t, period: 1.6) * 3), anchor: UnitPoint(x: 0.3, y: 0.9))
                        .offset(y: -bob * 16 * unit)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .aspectRatio(Self.canvas.width / Self.canvas.height, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("The pitch guide while singing")
    }

    private func layer(_ name: String) -> some View {
        Image(name).resizable().scaledToFit()
    }

    /// −1…1 sine wave with the given period in seconds.
    private func wave(_ t: TimeInterval, period: Double, phase: Double = 0) -> Double {
        sin((t / period + phase) * 2 * .pi)
    }
}

#Preview { PitchGuideIllustration(isActive: true).padding() }
