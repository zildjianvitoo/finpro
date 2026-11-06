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

    init(onBack: (() -> Void)? = nil, onContinue: @escaping () -> Void) {
        self.onBack = onBack
        self.onContinue = onContinue
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            VStack(alignment: .leading, spacing: 16) {
                Text("First, let's get to\nknow your voice.")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Color.brandPlum)

                Text("Discover the full range of your voice.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Start vocal test", action: onContinue)
                    .buttonStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
        .background(Color(.systemBackground))
    }

    private var topBar: some View {
        HStack {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }
}

#Preview {
    VocalRangeIntroView(onBack: {}) {}
}
