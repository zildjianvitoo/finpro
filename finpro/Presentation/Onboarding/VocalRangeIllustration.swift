//
//  VocalRangeIllustration.swift
//  finpro
//
//  Onboarding page 3 illustration, animated from its layers (docs/illustrations/Vercaapp 2.ai,
//  artboard 1): the ribbon drifts, the blob breathes, the mascot bobs and sways, and the slider
//  with its notes floats while its knob glides between the lowest and highest note. All layers
//  share one canvas size, so they stack in place. The track and knob are drawn here (taken out of
//  the slider layer) so the knob can move.
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
                    ZStack(alignment: .topLeading) {
                        layer("ob3-slider")
                        slider(knobY: knobY(t), unit: unit)
                    }
                    .offset(y: wave(t, period: 2.6, phase: 0.3) * 4 * unit)
                }
            }
        }
        .aspectRatio(354.0 / 396.0, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Finding your lowest and highest note")
    }

    // Slider geometry and colours from the artwork, in design points.
    private let trackFrame = CGRect(x: 238, y: 72, width: 38, height: 252)
    private let knobDiameter: CGFloat = 50.7
    private let knobTravel: CGFloat = 80
    private let trackFill = Color(red: 200 / 255, green: 172 / 255, blue: 193 / 255)
    private let trackStroke = Color(red: 147 / 255, green: 68 / 255, blue: 113 / 255)
    private let knobCenter = Color(red: 214 / 255, green: 251 / 255, blue: 98 / 255)
    private let knobEdge = Color(red: 238 / 255, green: 253 / 255, blue: 190 / 255)

    /// Knob centre: eases up to the highest note and down to the lowest, pausing briefly at each.
    private func knobY(_ t: TimeInterval) -> CGFloat {
        let swing = wave(t, period: 3.6)
        let eased = swing.sign == .minus ? -pow(-swing, 0.7) : pow(swing, 0.7)
        return trackFrame.midY - CGFloat(eased) * knobTravel
    }

    private func slider(knobY: CGFloat, unit: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Capsule()
                .fill(trackFill)
                .strokeBorder(trackStroke, lineWidth: 1 * unit)
                .frame(width: trackFrame.width * unit, height: trackFrame.height * unit)
                .offset(x: trackFrame.minX * unit, y: trackFrame.minY * unit)
            Circle()
                .fill(RadialGradient(colors: [knobCenter, knobEdge], center: .center,
                                     startRadius: 0, endRadius: knobDiameter / 2 * unit))
                .strokeBorder(.white, lineWidth: 1 * unit)
                .frame(width: knobDiameter * unit, height: knobDiameter * unit)
                .offset(x: (trackFrame.midX - knobDiameter / 2) * unit, y: (knobY - knobDiameter / 2) * unit)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
