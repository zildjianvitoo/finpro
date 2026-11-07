//
//  ComfortZoneBar.swift
//  finpro
//
//  Horizontal range bar on the result screen: dark edges past the sung range, amber for
//  reachable but less comfortable notes, lime for the comfort zone, with note labels below.
//

import SwiftUI

struct ComfortZoneBar: View {
    let lowestMIDI: Float
    let highestMIDI: Float
    let comfortLowMIDI: Float
    let comfortHighMIDI: Float

    private let trackHeight: CGFloat = 14
    private let markerHeight: CGFloat = 30
    private let markerWidth: CGFloat = 2
    /// Dark margin on each side of the sung range, as a fraction of the range span.
    private let edgePaddingFraction: Float = 0.15
    private let labelSpacing: CGFloat = 18

    var body: some View {
        VStack(spacing: labelSpacing) {
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    ZStack(alignment: .leading) {
                        Color.rangeEdge
                        segment(from: lowestMIDI, to: highestMIDI, width: width, color: .rangeStretch)
                        segment(from: comfortLowMIDI, to: comfortHighMIDI, width: width, color: .micIconHighlight)
                    }
                    .frame(height: trackHeight)
                    .clipShape(Capsule())

                    marker(at: comfortLowMIDI, width: width)
                    marker(at: comfortHighMIDI, width: width)
                }
                .frame(height: markerHeight)
            }
            .frame(height: markerHeight)

            labels
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Vocal range \(name(lowestMIDI)) to \(name(highestMIDI)), comfort zone \(name(comfortLowMIDI)) to \(name(comfortHighMIDI))")
    }

    private var labels: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                label(lowestMIDI, width: width)
                label(comfortLowMIDI, width: width)
                label((comfortLowMIDI + comfortHighMIDI) / 2, width: width)
                label(comfortHighMIDI, width: width)
                label(highestMIDI, width: width)
            }
        }
        .frame(height: 16)
        .font(.caption)
        .foregroundStyle(Color.plumInk)
    }

    // MARK: - Geometry

    private var domain: (low: Float, high: Float) {
        let padding = max(1, (highestMIDI - lowestMIDI) * edgePaddingFraction)
        return (lowestMIDI - padding, highestMIDI + padding)
    }

    private func x(for midi: Float, width: CGFloat) -> CGFloat {
        let (low, high) = domain
        return width * CGFloat((midi - low) / (high - low))
    }

    private func segment(from start: Float, to end: Float, width: CGFloat, color: Color) -> some View {
        let startX = x(for: start, width: width)
        return color
            .frame(width: max(0, x(for: end, width: width) - startX))
            .offset(x: startX)
    }

    private func marker(at midi: Float, width: CGFloat) -> some View {
        Rectangle()
            .fill(Color.primary)
            .frame(width: markerWidth, height: markerHeight)
            .offset(x: x(for: midi, width: width) - markerWidth / 2)
    }

    private func label(_ midi: Float, width: CGFloat) -> some View {
        Text(name(midi))
            .fixedSize()
            .position(x: x(for: midi, width: width), y: 8)
    }

    private func name(_ midi: Float) -> String {
        PitchMath.noteName(midi: Int(midi.rounded()))
    }
}

#Preview {
    ComfortZoneBar(lowestMIDI: 45, highestMIDI: 76, comfortLowMIDI: 48, comfortHighMIDI: 72)
        .padding(44)
        .background(Color.onboardingBackground)
}
