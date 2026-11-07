//
//  VocalRangeIntroView.swift
//  finpro
//
//  First screen of the vocal range test ("First, let's get to know your voice.").
//

import SwiftUI

struct VocalRangeIntroView: View {
    let onBack: (() -> Void)?
    let onContinue: () -> Void

    /// Inset of the buttons from the screen edge.
    private let buttonInset: CGFloat = 24
    /// Inset of the text, deeper than the buttons per the design (same as onboarding).
    private let contentInset: CGFloat = 44
    /// Gap between the top bar and the title, placing it in the upper third per the design.
    private let titleTopSpacing: CGFloat = 124
    /// Keeps the title in place whether or not the back button is shown (large glass button height).
    private let topBarHeight: CGFloat = 48

    init(onBack: (() -> Void)? = nil, onContinue: @escaping () -> Void) {
        self.onBack = onBack
        self.onContinue = onContinue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar

            VStack(alignment: .leading, spacing: 16) {
                Text("First, let’s get to\nknow your voice.")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Color.plumInk)

                Text("Discover the full range of your voice.")
                    .font(.footnote)
                    .foregroundStyle(Color.plumInkSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, contentInset)
            .padding(.top, titleTopSpacing)

            Spacer(minLength: 24)

            Button("Start vocal test", action: onContinue)
                .buttonStyle(.primaryDeep)
                .padding(.horizontal, buttonInset)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.onboardingBackground.ignoresSafeArea())
    }

    private var topBar: some View {
        HStack {
            if let onBack {
                LiquidGlassGroup {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                    }
                    .glassCircleButtonStyle()
                    .accessibilityLabel("Back")
                }
            }
            Spacer()
        }
        .frame(minHeight: topBarHeight)
        .padding(.horizontal, buttonInset)
    }
}

#Preview {
    VocalRangeIntroView(onBack: {}) {}
}
