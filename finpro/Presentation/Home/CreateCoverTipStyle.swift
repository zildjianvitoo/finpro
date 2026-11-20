//
//  CreateCoverTipStyle.swift
//  finpro
//

import SwiftUI
import TipKit

struct CreateCoverTipStyle: TipViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.title.font(.appFootnote).foregroundStyle(Color.primaryBrand)
            .frame(maxWidth: 180, alignment: .leading)
            .padding(AppSpacing.medium)
    }
}
