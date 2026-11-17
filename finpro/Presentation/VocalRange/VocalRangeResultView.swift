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
                        .buttonStyle(.appIcon(.glass)).accessibilityLabel("Back to highest note")
                    Spacer()
                }
                Text("Your vocal range").font(.appLargeTitle.weight(.regular))
                    .padding(.top, 32)
                Text("(\(note(range.lowestMIDI))-\(note(range.highestMIDI)))")
                    .font(.appDisplay(size: 60).weight(.semibold))
                    .minimumScaleFactor(0.6).lineLimit(1)
                    .padding(.top, -6)
            }
            .foregroundStyle(Color.primaryBrand)
            .padding(.horizontal, 16)
            GeometryReader { proxy in
                let low = min(36, Int(floor(Double(range.lowestMIDI) / 12)) * 12)
                let high = max(84, Int(ceil(Double(range.highestMIDI) / 12)) * 12)
                let span = CGFloat(high - low)
                let chartHeight = max(1, proxy.size.height - 40)
                ZStack(alignment: .topLeading) {
                    ForEach(Array(stride(from: low, through: high, by: 12)), id: \.self) { midi in
                        let y = CGFloat(high - midi) / span * chartHeight
                        // The outermost lines only frame the chart, so their labels are faded.
                        let isEdge = midi == low || midi == high
                        Rectangle().fill(Color.primary100).frame(height: 1).offset(y: y)
                        Text(PitchMath.noteName(midi: midi)).font(.appCaption.weight(.semibold))
                            .foregroundStyle(isEdge ? Color.primary100 : Color.primary400)
                            .offset(x: 79, y: y - 8)
                    }
                    Rectangle().fill(Color.primary100).frame(width: 1, height: chartHeight).offset(x: 101)
                    let top = CGFloat(high - Int(range.highestMIDI.rounded())) / span * chartHeight
                    let height = CGFloat(range.highestMIDI - range.lowestMIDI) / span * chartHeight
                    VStack {
                        Text(note(range.highestMIDI))
                        Spacer(minLength: 8)
                        Text(note(range.lowestMIDI))
                    }
                    .font(.appSubheadline.weight(.bold)).foregroundStyle(Color.primaryBrand)
                    .padding(.vertical, 4).frame(width: 44, height: max(56, height))
                    .background(Color.secBrand, in: Capsule())
                    .offset(x: proxy.size.width * 0.58, y: top)
                }
                .padding(.top, 20)
            }
            .padding(.horizontal, 16).padding(.top, 110).padding(.bottom, 32)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Measured range, \(note(range.lowestMIDI)) to \(note(range.highestMIDI))")
            VStack(spacing: 10) {
                Button("Start Cover", action: onDone).buttonStyle(.appPrimary)
                Button("Redo Test", action: onRetake).buttonStyle(.appSecondary)
            }
            .padding(.horizontal, 25).padding(.bottom, 16)
        }
        .background(Color.screenBackground.ignoresSafeArea())
    }
}
