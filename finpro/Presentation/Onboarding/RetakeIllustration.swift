//
//  RetakeIllustration.swift
//  finpro
//
//  Onboarding page 2 illustration ("Retake less"), animated from its layers
//  (docs/illustrations/ob2-*): the blob breathes, the ribbon drifts, the notes float, the spark
//  flickers, the mascot peeks over the clips card with its hands on the edge, and the card plays
//  natively. Moves only while the page is shown and never with Reduce Motion.
//

import SwiftUI

struct RetakeIllustration: View {
    /// The page is on screen.
    var isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Illustration canvas in pixels (all layers share it).
    private static let canvas = CGSize(width: 1063, height: 1189)
    /// Where the card sits, measured on ob2-full.
    private static let cardOrigin = CGPoint(x: 225, y: 474)
    /// Centre of the spark, so it flickers in place.
    private static let sparkAnchor = UnitPoint(x: 247 / 1063, y: 227 / 1189)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isActive || reduceMotion)) { context in
            let t = (isActive && !reduceMotion) ? context.date.timeIntervalSinceReferenceDate : 0
            GeometryReader { proxy in
                let unit = proxy.size.width / Self.canvas.width
                let card = RetakeIllustrationCard.size
                ZStack {
                    layer("ob2-blob")
                        .scaleEffect(1 + wave(t, period: 3.2) * 0.025)
                    layer("ob2-ribbon")
                        .offset(x: wave(t, period: 4.0) * 18 * unit)
                    layer("ob2-notes")
                        .offset(y: wave(t, period: 2.4, phase: 0.5) * 10 * unit)
                    layer("ob2-mascot")
                        .rotationEffect(.degrees(wave(t, period: 2.2) * 2), anchor: UnitPoint(x: 0.43, y: 0.45))
                        .offset(y: -abs(wave(t, period: 2.2)) * 10 * unit)
                    RetakeIllustrationCard(time: t, unit: unit)
                        .position(x: (Self.cardOrigin.x + card.width / 2) * unit, y: (Self.cardOrigin.y + card.height / 2) * unit)
                    layer("ob2-hands")
                    layer("ob2-spark")
                        .scaleEffect(1 + max(0, wave(t, period: 1.4)) * 0.18, anchor: Self.sparkAnchor)
                        .opacity(0.75 + 0.25 * abs(wave(t, period: 1.4)))
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .aspectRatio(Self.canvas.width / Self.canvas.height, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Choosing a clip to retake")
    }

    private func layer(_ name: String) -> some View {
        Image(name).resizable().scaledToFit()
    }

    /// −1…1 sine wave with the given period in seconds.
    private func wave(_ t: TimeInterval, period: Double, phase: Double = 0) -> Double {
        sin((t / period + phase) * 2 * .pi)
    }
}

#Preview { RetakeIllustration(isActive: true).padding() }
