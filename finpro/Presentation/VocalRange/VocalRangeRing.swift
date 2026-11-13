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
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: (!isListening && !showsMicrophoneIcon) || reduceMotion)) { context in
            let pulse = (isListening || showsMicrophoneIcon) && !reduceMotion
                ? 1 + 0.035 * sin(context.date.timeIntervalSinceReferenceDate * 4) : 1
            ZStack {
                Circle().fill(Color.primary200.opacity(0.6))
                    .scaleEffect(pulse)
                Circle().fill(Color.primaryBrand).padding(16)
                Circle().stroke(Color.primary800.opacity(0.5), lineWidth: 6).padding(18)
                if !showsMicrophoneIcon {
                    Circle().trim(from: 0, to: min(1, max(0, progress)))
                        .stroke(Color.secBrand, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90)).padding(18)
                        .animation(.linear(duration: 0.1), value: progress)
                }
                if showsMicrophoneIcon {
                    Image(systemName: "mic.fill").font(.system(size: 36))
                        .foregroundStyle(Color.secBrand)
                } else {
                    ListeningWaveform(isActive: isListening, hearsVoice: hearsVoice, barColor: .secBrand, levels: levels)
                        .frame(width: 94)
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
    }
}
