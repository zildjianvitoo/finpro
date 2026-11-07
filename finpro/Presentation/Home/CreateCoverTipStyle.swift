//
//  CreateCoverTipStyle.swift
//  finpro
//
//  Tip layout from the design: bold title, message, and a single "Got it" action
//  on the trailing side, without the default close button.
//

import SwiftUI
import TipKit

struct CreateCoverTipStyle: TipViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            configuration.title
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.plumInk)

            configuration.message?
                .font(.caption)
                .foregroundStyle(Color.plumInkSecondary)

            HStack {
                Spacer()
                ForEach(configuration.actions) { action in
                    Button(action: action.handler) {
                        action.label()
                    }
                    .font(.caption)
                    .foregroundStyle(Color.plumInk)
                }
            }
            .padding(.top, 4)
        }
        .padding(12)
        .frame(maxWidth: 180, alignment: .leading)
    }
}
