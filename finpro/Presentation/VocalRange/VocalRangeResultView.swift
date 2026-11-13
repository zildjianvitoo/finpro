//
//  VocalRangeResultView.swift
//  finpro
//

import SwiftUI

struct VocalRangeResultView: View {
    let range: VocalRange
    let isFemale: Bool
    let onDone: () -> Void
    /// Redo Test: the whole test again, from the intro.
    let onRetake: () -> Void
    /// Back to the highest-note step, to sing that note again.
    let onBack: () -> Void
    private func note(_ midi: Float) -> String { PitchMath.noteName(midi: Int(midi.rounded())) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                HStack {
                    Button(action: onBack) { Image(systemName: "chevron.left") }
                        .buttonStyle(.appIcon(.tinted)).accessibilityLabel("Back to highest note")
                    Spacer()
                }
                Text("Your vocal range").font(.appTitle1)
                Text("(\(note(range.lowestMIDI))-\(note(range.highestMIDI)))")
                    .font(.system(size: 48, weight: .semibold))
                    .minimumScaleFactor(0.6).lineLimit(1)
                Spacer(minLength: 36)
            }
            .foregroundStyle(Color.primaryDark)
            .padding(.horizontal, 24)
            .frame(height: 260)
            .background {
                VocalResultHeaderShape()
                    .fill(Color.secBrand).ignoresSafeArea(edges: .top)
            }
            GeometryReader { proxy in
                let low = min(36, Int(floor(Double(range.lowestMIDI) / 12)) * 12)
                let high = max(84, Int(ceil(Double(range.highestMIDI) / 12)) * 12)
                let span = CGFloat(high - low)
                let chartHeight = max(1, proxy.size.height - 40)
                ZStack(alignment: .topLeading) {
                    ForEach(Array(stride(from: low, through: high, by: 12)), id: \.self) { midi in
                        let y = CGFloat(high - midi) / span * chartHeight
                        Rectangle().fill(Color.primary100).frame(height: 1).offset(y: y)
                        Text(PitchMath.noteName(midi: midi)).font(.appCaption2)
                            .foregroundStyle(Color.secondaryText).offset(x: 60, y: y - 14)
                    }
                    let top = CGFloat(high - Int(range.highestMIDI.rounded())) / span * chartHeight
                    let height = CGFloat(range.highestMIDI - range.lowestMIDI) / span * chartHeight
                    VStack {
                        Text(note(range.highestMIDI))
                        Spacer(minLength: 8)
                        Text(note(range.lowestMIDI))
                    }
                    .font(.appCaption2).foregroundStyle(Color.primaryDark)
                    .padding(.vertical, 8).frame(width: 40, height: max(48, height))
                    .background(Color.secBrand, in: Capsule())
                    .offset(x: proxy.size.width * 0.6, y: top)
                }
                .padding(.top, 20)
            }
            .padding(.horizontal, 24).padding(.top, 32)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Measured range, \(note(range.lowestMIDI)) to \(note(range.highestMIDI))")
            VStack(spacing: 10) {
                Button("Start Cover", action: onDone).buttonStyle(.appPrimary)
                Button("Redo Test", action: onRetake).buttonStyle(.appSecondary)
            }
            .padding(.horizontal, 24).padding(.bottom, 12)
        }
        .background(Color.screenBackground.ignoresSafeArea())
    }
}
