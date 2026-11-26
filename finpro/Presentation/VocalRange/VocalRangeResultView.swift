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
    var backAccessibilityLabel: String = "Back to highest note"
    var isSwipeBackEnabled: Bool = true
    var onSwipeProgress: ((CGFloat) -> Void)? = nil
    /// Entrance: the card appears, the mascot peeks up from behind it, then the notes float.
    @State private var appeared = false
    @State private var floating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private func note(_ midi: Float) -> String { PitchMath.noteName(midi: Int(midi.rounded())) }

    var body: some View {
        VStack(spacing: 0) {
            header
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
                    .font(.appSubheadline.weight(.bold)).foregroundStyle(Color.primary500)
                    .padding(.vertical, 4).frame(width: 44, height: max(56, height))
                    .background(Color.secBrand, in: Capsule())
                    .offset(x: proxy.size.width * 0.58, y: top)
                }
                .padding(.top, 20)
            }
            .padding(.horizontal, 16).padding(.top, Self.chartTop).padding(.bottom, 32)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Measured range, \(note(range.lowestMIDI)) to \(note(range.highestMIDI))")
            VStack(spacing: 8) {
                Button("Start Cover", action: onDone).buttonStyle(.appPrimary)
                Button("Redo Test", action: onRetake).buttonStyle(.appSecondary)
            }
            .padding(.horizontal, 25).padding(.bottom, 16)
        }
        .background(Color.screenBackground.ignoresSafeArea())
        .edgeSwipeBack(isEnabled: isSwipeBackEnabled, onProgress: onSwipeProgress, action: onBack)
    }

    // Positions from the 2.6 design frame, relative to the top of the safe area (y 62) and the
    // screen's centre (x 201).
    private static let headerHeight: CGFloat = 299
    private static let cardSize = CGSize(width: 280, height: 149)
    private static let cardTop: CGFloat = 150
    /// Space between the card and the chart's top line (the chart draws its lines 20 pt down).
    private static let chartTop: CGFloat = 12

    /// The mascot peeking over the result card, with music notes around (design 2.6).
    private var header: some View {
        ZStack(alignment: .top) {
            Image("ResultNotes").resizable().frame(width: 308, height: 195)
                .offset(x: -21, y: 24 + (floating ? -6 : 0))
                .opacity(appeared ? 1 : 0)
                .accessibilityHidden(true)
            Image("ResultMascot").resizable().scaledToFit().frame(width: 125, height: 161)
                .offset(x: -51, y: 18 + (appeared ? 0 : 60))
                .accessibilityHidden(true)
            VStack(spacing: 0) {
                Text("Your vocal range:").font(.appTitle2.weight(.regular))
                    .frame(height: 41)
                Text("(\(note(range.lowestMIDI))-\(note(range.highestMIDI)))")
                    .font(.appDisplay(size: 60).weight(.semibold))
                    .minimumScaleFactor(0.6).lineLimit(1)
                    .padding(.top, 6)
            }
            .foregroundStyle(Color.plumNight)
            .padding(.top, 22).padding(.horizontal, AppSpacing.medium)
            .frame(width: Self.cardSize.width, height: Self.cardSize.height, alignment: .top)
            .background(Color.secondaryButton, in: RoundedRectangle(cornerRadius: AppRadius.large))
            .accessibilityElement(children: .combine)
            .scaleEffect(appeared ? 1 : 0.9)
            .opacity(appeared ? 1 : 0)
            .offset(y: Self.cardTop)
            Image("ResultHands").resizable().scaledToFit().frame(width: 98, height: 34)
                .offset(x: -57, y: 136 + (appeared ? 0 : 20))
                .opacity(appeared ? 1 : 0)
                .accessibilityHidden(true)
            HStack {
                Button(action: onBack) { Image(systemName: "chevron.left") }
                    .buttonStyle(.appIcon(.glass)).accessibilityLabel(backAccessibilityLabel)
                Spacer()
            }
            .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity).frame(height: Self.headerHeight, alignment: .top)
        .onAppear {
            guard !reduceMotion else { appeared = true; return }
            withAnimation(.spring(duration: 0.6, bounce: 0.35).delay(0.1)) { appeared = true }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true).delay(0.7)) { floating = true }
        }
    }
}
