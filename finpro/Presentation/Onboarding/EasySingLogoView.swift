//
//  EasySingLogoView.swift
//  finpro
//
//  EasySing brand logo with stylized waveform bars.
//

import SwiftUI

struct EasySingLogoView: View {
    /// Bar heights in points, left to right, as drawn in the splash design.
    private let barHeights: [CGFloat] = [18, 44, 80, 42, 62, 24]

    var body: some View {
        VStack(spacing: 24) {
            HStack(spacing: 8) {
                ForEach(barHeights.indices, id: \.self) { index in
                    Capsule()
                        .frame(width: 6, height: barHeights[index])
                }
            }
            .accessibilityHidden(true)

            Text("EasySing")
                .font(.system(size: 34, weight: .bold))
        }
        .foregroundStyle(Color.primaryDark)
    }
}

#Preview {
    EasySingLogoView()
}
