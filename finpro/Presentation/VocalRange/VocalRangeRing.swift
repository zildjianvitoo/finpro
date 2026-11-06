//
//  VocalRangeRing.swift
//  finpro
//
//  The listening ring: a soft lilac outer halo and a dark plum inner disc
//  with the chartreuse waveform or microphone icon.
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

    private static let discDiameter: CGFloat = 124
    private static let haloDiameter: CGFloat = 156

    var body: some View {
        ZStack {
            // Soft lilac outer halo band
            Circle()
                .fill(Color(red: 0.78, green: 0.70, blue: 0.76).opacity(0.75))
                .frame(width: Self.haloDiameter, height: Self.haloDiameter)

            // Inner dark plum disc
            Circle()
                .fill(Color.brandPlum)
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                .frame(width: Self.discDiameter, height: Self.discDiameter)

            if showsMicrophoneIcon {
                Image(systemName: "mic.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Color.micIconHighlight)
            } else {
                ListeningWaveform(isActive: isListening, hearsVoice: hearsVoice)
                    .frame(width: Self.discDiameter - 44)
            }
        }
        .frame(height: Self.haloDiameter + 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
    }
}
