//
//  OnboardingProTipView.swift
//  finpro
//
//  Dark "Pro tip" strip laid over the bottom of an onboarding illustration.
//

import SwiftUI

struct OnboardingProTipView: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lightbulb.max")
                .font(.system(size: 15, weight: .regular))
                .accessibilityHidden(true)

            Text(text)
                .font(.caption2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.proTipBackground)
        )
    }
}

#Preview {
    OnboardingProTipView(text: "Pro tip: Connect your wired headphones before you start recording.")
        .padding()
        .background(Color.plumDeep)
}
