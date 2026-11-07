//
//  ListeningWaveform.swift
//  finpro
//
//  Decorative waveform with a center playhead inside the vocal range ring. It moves while
//  listening and gets taller while a voice is heard. It does not show real audio levels.
//

import SwiftUI

struct ListeningWaveform: View {
    var isActive: Bool
    var hearsVoice: Bool
    var barColor: Color = Color.micIconHighlight

    private static let barCount = 25
    private static let barWidth: CGFloat = 2
    private static let barSpacing: CGFloat = 2
    private static let maxHeight: CGFloat = 48

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isActive)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            ZStack {
                HStack(spacing: Self.barSpacing) {
                    ForEach(0..<Self.barCount, id: \.self) { index in
                        Capsule()
                            .fill(barColor.opacity(opacity(for: index)))
                            .frame(width: Self.barWidth, height: height(for: index, phase: phase))
                    }
                }
                playhead
            }
            .frame(height: Self.maxHeight + 16)
        }
        .animation(.easeOut(duration: 0.2), value: hearsVoice)
        .accessibilityHidden(true)
    }

    private var playhead: some View {
        VStack(spacing: 0) {
            Circle().frame(width: 5, height: 5)
            Rectangle().frame(width: 1.5)
            Circle().frame(width: 5, height: 5)
        }
        .foregroundStyle(barColor.opacity(0.8))
        .frame(height: Self.maxHeight + 14)
    }

    /// 0 at the center bar, 1 at either end.
    private func distance(for index: Int) -> Double {
        let middle = Double(Self.barCount - 1) / 2
        return abs(Double(index) - middle) / middle
    }

    private func opacity(for index: Int) -> Double {
        1 - 0.6 * distance(for: index)
    }

    private func height(for index: Int, phase: TimeInterval) -> CGFloat {
        let x = distance(for: index)
        let envelope = exp(-x * x * 3)
        let motion = isActive ? 0.55 + 0.45 * sin(phase * 6 + Double(index) * 0.9) : 0.3
        let loudness = hearsVoice ? 1.0 : 0.4
        return 4 + (Self.maxHeight - 4) * envelope * motion * loudness
    }
}
