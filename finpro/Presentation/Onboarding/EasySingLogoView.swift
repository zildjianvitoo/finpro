//
//  EasySingLogoView.swift
//  finpro
//
//  EasySing brand logo with stylized waveform bars.
//

import SwiftUI

struct EasySingLogoView: View {
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 6) {
                bar(height: 18)
                bar(height: 32)
                bar(height: 48)
                bar(height: 32)
                bar(height: 18)
            }
            .foregroundStyle(Color.primary)

            Text("EasySing")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.primary)
        }
    }

    private func bar(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .frame(width: 5, height: height)
    }
}

#Preview {
    EasySingLogoView()
}
