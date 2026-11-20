//
//  BrandLogoView.swift
//  finpro
//
//  verca brand logo: the mascot above the wordmark (splash and welcome screens).
//

import SwiftUI

struct BrandLogoView: View {
    var body: some View {
        VStack(spacing: 27) {
            Image("BrandMascot")
                .resizable()
                .scaledToFit()
                .frame(height: 100)
                .accessibilityHidden(true)

            Text("verca")
                .font(.appLargeTitle)
                .foregroundStyle(Color.primaryBrand)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    BrandLogoView()
}
