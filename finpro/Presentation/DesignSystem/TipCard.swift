//
//  TipCard.swift
//  finpro
//
//  Rounded hint card: icon, divider, an optional title and guidance.
//

import SwiftUI

struct TipCard: View {
    var title: String? = nil
    let message: String
    var systemImage = "lightbulb.max"

    private let cornerRadius: CGFloat = 12
    /// Keeps one- and two-line tips the same height as three-line ones, per the design.
    private let minimumHeight: CGFloat = 52

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(Color.plumInk)
                .frame(minWidth: 24)
                .accessibilityHidden(true)

            Rectangle()
                .fill(Color.plumInkSecondary)
                .frame(width: 1)
                .frame(maxHeight: 28)

            VStack(alignment: .leading, spacing: 2) {
                if let title, !title.isEmpty {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.plumInk)
                }
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(Color.plumInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: minimumHeight)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.surfaceElevated)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        )
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    TipCard(message: "Hold at the lowest note you can make comfortably, without vocal fry or strain.")
        .padding()
        .background(Color.onboardingBackground)
}
