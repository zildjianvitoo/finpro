//
//  VocalRangeRing.swift
//  finpro
//

import SwiftUI

struct VocalRangeRing: View {
    var progress: Double
    var isListening: Bool
    var hearsVoice: Bool
    var label: String
    var showsMicrophoneIcon = false
    var levels: [Float] = []
    var diameter: CGFloat = AppLayout.microphoneDiameter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !isListening || reduceMotion)) { context in
            // The halo breathes only while the microphone listens.
            let pulse = isListening && !reduceMotion
                ? 1 + 0.035 * sin(context.date.timeIntervalSinceReferenceDate * 4) : 1
            // Sizes as shares of the diameter, so the ring keeps the design's proportions at any size.
            let discInset = diameter * 0.094
            let ringInset = diameter * 0.106
            ZStack {
                Circle().fill(Color.ringHalo)
                    .scaleEffect(pulse)
                Circle().fill(Color.primaryButton).padding(discInset)
                Circle().stroke(Color.ringStroke, lineWidth: 6).padding(ringInset)
                if !showsMicrophoneIcon {
                    Circle().trim(from: 0, to: min(1, max(0, progress)))
                        .stroke(Color.secBrand, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90)).padding(ringInset)
                        .animation(.linear(duration: 0.1), value: progress)
                }
                if showsMicrophoneIcon {
                    // White, as in draft 2.5b.
                    Image(systemName: "mic.fill").font(.system(size: diameter * 0.23))
                        .foregroundStyle(.white)
                } else {
                    ListeningWaveform(isActive: isListening, hearsVoice: hearsVoice, barColor: .secBrand, levels: levels)
                        .frame(width: diameter * 0.55)
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
    }
}
