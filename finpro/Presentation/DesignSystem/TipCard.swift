//
//  TipCard.swift
//  finpro
//
//  Rounded hint card: icon, divider, a short title and one line of guidance.
//

import SwiftUI

struct TipCard: View {
    let title: String
    let message: String
    var systemImage = "waveform"

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.ringTrack.opacity(0.6)))
            Rectangle()
                .fill(Color.ringTrack)
                .frame(width: 1, height: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.cardBackground))
        .accessibilityElement(children: .combine)
    }
}
