//
//  VocalRangeIntroView.swift
//  finpro
//

import SwiftUI

struct VocalRangeIntroView: View {
    var isActive = true
    var onBack: (() -> Void)? = nil
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let onBack {
                    Button(action: onBack) { Image(systemName: "chevron.left") }
                        .buttonStyle(.appIcon(.glass)).accessibilityLabel("Back")
                }
                Spacer()
            }
            .frame(height: 44)
            .padding(.horizontal, AppSpacing.regular)

            ViewThatFits(in: .vertical) {
                introduction
                ScrollView { introduction }
            }
            .padding(.horizontal, AppSpacing.large)
            .padding(.top, AppSpacing.large)
            .frame(maxHeight: .infinity)

            Button("Start vocal test", action: onContinue)
                .buttonStyle(.appPrimary)
                .padding(.horizontal, 25)
                .padding(.bottom, AppSpacing.medium)
        }
        .background(Color.screenBackground.ignoresSafeArea())
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Let's Get Your\nVoice Ready")
                .font(.appLargeTitle)
                .foregroundStyle(Color.primaryBrand)
                .accessibilityAddTraits(.isHeader)
            Text("We'll find your vocal range and adjust song keys to fit your voice.")
                .font(.appBody)
                .foregroundStyle(Color.primary300)
                .padding(.top, AppSpacing.small)
            VocalRangeIllustration(isActive: isActive)
                .frame(maxWidth: .infinity)
                .padding(.top, 36)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview { VocalRangeIntroView(onBack: {}) {} }
