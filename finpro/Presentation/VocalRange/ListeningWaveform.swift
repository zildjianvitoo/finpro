//
//  ListeningWaveform.swift
//  finpro
//

import SwiftUI

/// RMS envelope samples from the active microphone stream, with a center playhead.
struct ListeningWaveform: View {
    var isActive: Bool
    var hearsVoice: Bool
    var barColor: Color = .secBrand
    var levels: [Float] = []

    var body: some View {
        ZStack {
            HStack(spacing: 2) {
                ForEach(0..<25) { index in
                    let offset = index - (25 - levels.count)
                    let level = offset >= 0 && offset < levels.count ? levels[offset] : 0
                    Capsule().fill(barColor.opacity(0.45 + 0.55 * Double(level)))
                        .frame(width: 2, height: max(2, CGFloat(level) * 48))
                }
            }
            VStack(spacing: 0) {
                Circle().frame(width: 5, height: 5)
                Rectangle().frame(width: 1.5)
                Circle().frame(width: 5, height: 5)
            }
            .foregroundStyle(barColor.opacity(0.8)).frame(height: 62)
        }
        .frame(height: 64).accessibilityHidden(true)
    }
}
