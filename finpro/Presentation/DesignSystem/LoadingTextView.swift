//
//  LoadingTextView.swift
//  finpro
//
//  The text under the loading mascot: its letters ripple like a sung line, the ellipsis dots hop
//  one after another, and the percentage (when there is one) rolls to each new value.
//

import SwiftUI

struct LoadingTextView: View {
    let title: String
    /// 0...1, shown as a percentage after the title; nil shows the title only.
    var progress: Double?
    var font: Font = .subheadline.weight(.semibold)
    /// On for white text over the loading overlay; off for dark text on a light background.
    var shadowed = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Seconds for one ripple to run along the letters.
    private static let ripplePeriod: Double = 1.6
    /// Phase step between neighbouring letters (radians).
    private static let letterLag: Double = 0.32
    private static let rippleHeight: CGFloat = 2.5
    private static let dotHeight: CGFloat = 4
    private static let dotCount = 3
    private static let restingOpacity: Double = 0.7
    /// Soft shadow that keeps white text readable over busy content under the overlay.
    private static let shadowOpacity: Double = 0.35
    private static let shadowRadius: CGFloat = 3

    private var letters: [String] {
        var text = title
        while text.hasSuffix("…") || text.hasSuffix(".") { text.removeLast() }
        return text.map(String.init)
    }

    var body: some View {
        HStack(spacing: 0) {
            TimelineView(.animation(paused: reduceMotion)) { context in
                let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                HStack(spacing: 0) {
                    ForEach(Array(letters.enumerated()), id: \.offset) { index, letter in
                        let lift = Self.lift(time: time, index: index)
                        Text(letter)
                            .offset(y: -lift * Self.rippleHeight)
                            .opacity(Self.restingOpacity + (1 - Self.restingOpacity) * lift)
                    }
                    ForEach(0..<Self.dotCount, id: \.self) { dot in
                        let lift = Self.lift(time: time, index: letters.count + dot * 2)
                        Text(".")
                            .offset(y: -lift * Self.dotHeight)
                    }
                }
            }
            if let progress {
                Text(" " + progress.formatted(.percent.precision(.fractionLength(0))))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: progress))
                    .animation(.snappy, value: progress)
            }
        }
        .font(font)
        .shadow(color: .black.opacity(shadowed ? Self.shadowOpacity : 0), radius: Self.shadowRadius)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(progress.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "")
    }

    /// 0 at rest, 1 at the top of the ripple for that letter.
    private static func lift(time: TimeInterval, index: Int) -> CGFloat {
        let phase = 2 * .pi * time / ripplePeriod - Double(index) * letterLag
        return CGFloat(max(0, sin(phase)))
    }
}

#Preview {
    VStack(spacing: 20) {
        LoadingTextView(title: "Merging your recording…", progress: 0.18)
        LoadingTextView(title: "Finding lyrics…")
    }
    .foregroundStyle(.white)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.loadingOverlay.opacity(AppLayout.loadingOverlayOpacity))
}
