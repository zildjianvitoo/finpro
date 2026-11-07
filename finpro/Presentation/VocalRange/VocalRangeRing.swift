//
//  VocalRangeRing.swift
//  finpro
//
//  The listening ring: a soft lilac outer halo, a dark stroke ring and a plum inner disc
//  with the chartreuse waveform or microphone icon.
//

import SwiftUI

struct VocalRangeRing: View {
    /// 0...1, how much of the required stable hold is done.
    var progress: Double
    var isListening: Bool
    var hearsVoice: Bool
    var label: String
    /// Shows a microphone icon in the center disc for warm-up.
    var showsMicrophoneIcon = false

    private static let haloDiameter: CGFloat = 196
    private static let strokeDiameter: CGFloat = 164
    private static let discDiameter: CGFloat = 151
    private static let waveformWidth: CGFloat = 100

    @ScaledMetric(relativeTo: .largeTitle) private var micSize: CGFloat = 32

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.ringHalo)
                .frame(width: Self.haloDiameter, height: Self.haloDiameter)

            Circle()
                .fill(Color.ringStroke)
                .frame(width: Self.strokeDiameter, height: Self.strokeDiameter)

            Circle()
                .fill(Color.ringDisc)
                .frame(width: Self.discDiameter, height: Self.discDiameter)

            if showsMicrophoneIcon {
                Image(systemName: "mic")
                    .font(.system(size: micSize, weight: .regular))
                    .foregroundStyle(Color.micIconHighlight)
            } else {
                ListeningWaveform(isActive: isListening, hearsVoice: hearsVoice)
                    .frame(width: Self.waveformWidth)
            }
        }
        .frame(width: Self.haloDiameter, height: Self.haloDiameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
    }
}
