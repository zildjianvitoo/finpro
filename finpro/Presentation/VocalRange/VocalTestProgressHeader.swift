//
//  VocalTestProgressHeader.swift
//  finpro
//

import SwiftUI

struct VocalTestProgressHeader: View {
    let step: Int
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.regular) {
            Button(action: onBack) { Image(systemName: "chevron.left") }
                .buttonStyle(.appIcon(.glass))
                .accessibilityLabel("Back")
            GeometryReader { proxy in
                Capsule().fill(Color.primary100)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Color.primaryBrand)
                            .frame(width: proxy.size.width * CGFloat(step) / 3)
                    }
            }
            .frame(height: 4)
            .accessibilityLabel("Vocal test progress")
            .accessibilityValue("Step \(step) of 3")
        }
        .frame(height: 44)
        .padding(.leading, AppSpacing.regular)
        .padding(.trailing, 32)
    }
}
