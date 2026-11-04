//
//  CircleIconButton.swift
//  finpro
//
//  Round outlined icon button for the top bar (back, help).
//

import SwiftUI

struct CircleIconButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.surfaceElevated))
                .overlay(Circle().strokeBorder(Color.ringTrack, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
