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
            .frame(maxHeight: .infinity, alignment: .top)

            Button("Let's Begin", action: onContinue)
                .buttonStyle(.appPrimary)
                .padding(.horizontal, 25)
                .padding(.bottom, 20)
        }
        .background(Color.screenBackground.ignoresSafeArea())
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Let's Get Your Voice\nReady")
                .font(.appLargeTitle)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            Text("We'll find your vocal range and adjust song keys to make them more comfortable for you to sing.")
                .font(.appBody)
                .foregroundStyle(Color.plumNight)
                .padding(.top, AppSpacing.small)
            VocalRangeIllustration(isActive: isActive)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview { VocalRangeIntroView(onBack: {}) {} }
