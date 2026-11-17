//
//  VocalRangeIllustration.swift
//  finpro
//
//  Onboarding page 3 illustration, animated from its layers (docs/illustrations/Vercaapp 2.ai,
//  artboard 1): the ribbon drifts, the blob breathes, the mascot bobs and sways, and the slider
//  with its notes floats. All layers share one canvas size, so they stack in place.
//  Moves only while the page is shown and never with Reduce Motion.
//

import SwiftUI

struct VocalRangeIllustration: View {
    /// The page is on screen.
    var isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isActive || reduceMotion)) { context in
            let t = (isActive && !reduceMotion) ? context.date.timeIntervalSinceReferenceDate : 0
            GeometryReader { proxy in
                let unit = proxy.size.width / 354   // design points → view points
                ZStack {
                    layer("ob3-ribbon")
                        .offset(x: wave(t, period: 4.0) * 6 * unit)
                    layer("ob3-blob")
                        .scaleEffect(1 + wave(t, period: 3.2) * 0.025)
                    layer("ob3-mascot")
                        .rotationEffect(.degrees(wave(t, period: 1.8) * 3), anchor: UnitPoint(x: 0.3, y: 0.85))
                        .offset(y: -abs(wave(t, period: 1.8)) * 6 * unit)
                    layer("ob3-slider")
                        .offset(y: wave(t, period: 2.6, phase: 0.3) * 4 * unit)
                }
            }
        }
        .aspectRatio(354.0 / 396.0, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Finding your lowest and highest note")
    }

    private func layer(_ name: String) -> some View {
        Image(name).resizable().scaledToFit()
    }

    /// −1…1 sine wave with the given period in seconds.
    private func wave(_ t: TimeInterval, period: Double, phase: Double = 0) -> Double {
        sin((t / period + phase) * 2 * .pi)
    }
}

#Preview { VocalRangeIllustration(isActive: true).padding() }
