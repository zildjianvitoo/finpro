//
//  VocalRangeIntroView.swift
//  finpro
//

import SwiftUI

struct VocalRangeIntroView: View {
    var onBack: (() -> Void)? = nil
    let onContinue: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let titleSize = AppTypography.fittedVocalDisplaySize(width: proxy.size.width - AppSpacing.textInset * 2)
            let lineAdvance = AppTypography.vocalDisplayLineAdvance(size: titleSize)
            let ink = AppTypography.vocalDisplayInkInsets(size: titleSize)
            let shapeTop = proxy.size.height * 0.4
            let shapeHeight = proxy.size.height - shapeTop + proxy.safeAreaInsets.bottom
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    if let onBack {
                        Button(action: onBack) { Image(systemName: "chevron.left") }
                            .buttonStyle(.appIcon(.glass)).accessibilityLabel("Back")
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: 44)
                .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 0) {
                    Text("First,")
                    Text("Meet")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, min(AppSpacing.spacious + AppSpacing.regular, proxy.size.height * 0.075))
                }
                .font(.appDisplay(size: titleSize))
                .foregroundStyle(Color.primaryBrand)
                .padding(.leading, 54).padding(.trailing, 44)
                .padding(.top, 8)

                Spacer(minLength: 16)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Your").foregroundStyle(Color.primary300)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(height: lineAdvance, alignment: .topLeading)
                    Text("vocal").foregroundStyle(Color.primaryBrand)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(height: lineAdvance, alignment: .topLeading)
                    Text("range").foregroundStyle(Color.primaryBrand)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(height: lineAdvance, alignment: .topLeading)
                }
                .font(.appDisplay(size: titleSize))
                .padding(.horizontal, 55)
                // Laid out by the ink: the gaps above "Your" and below "range" match (design).
                .padding(.top, -ink.top).padding(.bottom, -ink.bottom)
                .accessibilityElement(children: .combine)

                Spacer(minLength: 16)

                Button("Start vocal test", action: onContinue)
                    .buttonStyle(.appPrimary)
                    .shadow(color: Color.primary100.opacity(0.2), radius: 3, y: 1)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .background(alignment: .topLeading) {
                VocalIntroBackground().fill(Color.primary100)
                    .frame(width: proxy.size.width, height: shapeHeight)
                    .offset(y: shapeTop)
                    .allowsHitTesting(false)
            }

        }
        .background(Color.screenBackground.ignoresSafeArea())
    }
}

#Preview { VocalRangeIntroView(onBack: {}) {} }
