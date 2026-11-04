//
//  VocalRangeIntroView.swift
//  finpro
//
//  First screen of the vocal range test.
//

import SwiftUI

struct VocalRangeIntroView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Find your\nvocal range")
                .font(.largeTitle.bold())
            Text("Take a quick test to know your comfortable range.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Continue", action: onContinue)
                .buttonStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 120)
        .padding(.bottom, 16)
    }
}

#Preview {
    VocalRangeIntroView {}
}
