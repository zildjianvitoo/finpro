//
//  VocalPitchBar.swift
//  finpro
//
//  Live pitch on the lowest/highest note steps (Sketch "TestFlight UT" 2.4 / 2.5): the note and
//  its frequency above a lime bar whose knob moves right as the voice goes up.
//

import SwiftUI

struct VocalPitchBar: View {
    let midi: Float?
    let referenceMIDI: Float
    @State private var lastHeardMIDI: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Semitones shown on each side of the reference note (about an octave and a half).
    private static let halfSpan: Double = 18
    private static let barHeight: CGFloat = 20
    private static let tickWidth: CGFloat = 5
    private static let tickSpacing: CGFloat = 13

    private var position: LivePitchPositionUseCase.Position? { LivePitchPositionUseCase().execute(midi: midi) }
    private var reference: Double {
        referenceMIDI.isFinite ? min(127, max(0, Double(referenceMIDI))) : 57
    }
    private var shownMIDI: Double? { position?.noteMIDI ?? lastHeardMIDI }
    /// 0...1 along the bar.
    private var fraction: Double {
        guard let shownMIDI else { return 0.5 }
        return min(1, max(0, (shownMIDI - reference + Self.halfSpan) / (Self.halfSpan * 2)))
    }

    var body: some View {
        VStack(spacing: AppSpacing.regular) {
            VStack(spacing: 2) {
                Text(shownMIDI.map { PitchMath.noteName(midi: Int($0.rounded())) } ?? "–")
                    .font(.appTitle2.weight(.bold)).foregroundStyle(Color.primaryBrand)
                Text(shownMIDI.map { "(\(Int(PitchMath.frequency(fromMIDI: $0).rounded())) Hz)" } ?? " ")
                    .font(.appSubheadline).foregroundStyle(Color.secondaryText)
            }
            .contentTransition(.numericText())
            GeometryReader { proxy in
                let knob = Self.barHeight / 2 + (proxy.size.width - Self.barHeight) * fraction
                ZStack(alignment: .leading) {
                    ticks(from: knob + Self.barHeight / 2 + 4, width: proxy.size.width)
                    Capsule().fill(Color.secBrand)
                        .frame(width: knob + Self.barHeight / 2)
                    Circle().fill(Color.primaryButton)
                        .overlay(Circle().fill(Color.secBrand).padding(5))
                        .frame(width: Self.barHeight, height: Self.barHeight)
                        .offset(x: knob - Self.barHeight / 2)
                        .opacity(shownMIDI == nil ? 0.4 : 1)
                }
            }
            .frame(height: Self.barHeight)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: fraction)
        .onChange(of: midi, initial: true) { _, _ in
            if let position { lastHeardMIDI = position.noteMIDI }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Detected pitch")
        .accessibilityValue(spokenDescription)
    }

    /// Tick marks fill the bar to the right of the knob.
    private func ticks(from start: CGFloat, width: CGFloat) -> some View {
        let count = max(0, Int((width - start + Self.tickSpacing - Self.tickWidth) / Self.tickSpacing))
        return HStack(spacing: Self.tickSpacing - Self.tickWidth) {
            ForEach(0..<count, id: \.self) { _ in
                Capsule().fill(Color.primaryButton).frame(width: Self.tickWidth)
            }
        }
        .frame(width: width - start, alignment: .trailing)
        .offset(x: start)
    }

    private var spokenDescription: String {
        guard let position else { return "No voice detected" }
        return "\(PitchMath.noteName(midi: position.nearestNote)), \(Int(PitchMath.frequency(fromMIDI: position.midi))) hertz"
    }
}

#Preview {
    VStack(spacing: 40) {
        VocalPitchBar(midi: 40, referenceMIDI: 50)
        VocalPitchBar(midi: nil, referenceMIDI: 57)
    }
    .padding(54)
}
