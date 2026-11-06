//
//  VocalRangeRing.swift
//  finpro
//
//  The listening ring: a soft glow, a track that fills with the hold progress, and a white
//  disc with the waveform and a short label (live note, "Hmm…", or the captured result).
//

import SwiftUI

struct VocalRangeRing: View {
    /// 0...1, how much of the required stable hold is done.
    var progress: Double
    var isListening: Bool
    var hearsVoice: Bool
    var label: String
    /// Shows the label large and bold (a captured note or the final range).
    var emphasizesLabel = false
    /// Shows a microphone icon in the center disc for warm-up.
    var showsMicrophoneIcon = false

    private static let ringDiameter: CGFloat = 200
    private static let lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color.listeningGlow, Color.listeningGlow.opacity(0)],
                                     center: .center, startRadius: Self.ringDiameter * 0.4,
                                     endRadius: Self.ringDiameter * 0.8))
                .frame(width: Self.ringDiameter * 1.6, height: Self.ringDiameter * 1.6)
            Circle()
                .stroke(Color.ringTrack, lineWidth: Self.lineWidth)
                .frame(width: Self.ringDiameter, height: Self.ringDiameter)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(Color.ringProgress, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: Self.ringDiameter, height: Self.ringDiameter)
                .animation(.easeOut(duration: 0.15), value: progress)
            Circle()
                .fill(Color.brandPlum)
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                .frame(width: Self.ringDiameter - 34, height: Self.ringDiameter - 34)

            if showsMicrophoneIcon {
                Image(systemName: "mic.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(Color.micIconHighlight)
            } else {
                VStack(spacing: 12) {
                    ListeningWaveform(isActive: isListening, hearsVoice: hearsVoice)
                        .frame(width: Self.ringDiameter - 70)
                }
            }
        }
        .frame(height: Self.ringDiameter * 1.4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
    }
}
