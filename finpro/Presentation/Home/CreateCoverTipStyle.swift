//
//  CreateCoverTipStyle.swift
//  finpro
//

import SwiftUI
import TipKit

struct CreateCoverTipStyle: TipViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.title.font(.appSubheadline).foregroundStyle(Color.primary)
            .frame(maxWidth: 180, alignment: .leading)
            .padding(AppSpacing.medium)
    }
}
