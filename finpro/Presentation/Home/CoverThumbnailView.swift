//
//  CoverThumbnailView.swift
//  finpro
//

import SwiftUI

struct CoverThumbnailView: View {
    @State var viewModel: CoverThumbnailViewModel
    var body: some View {
        Color.secondaryButton.overlay {
            if let image = viewModel.image {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            } else {
                Image(systemName: "video").font(.appTitle2).foregroundStyle(Color.secondaryText)
            }
        }
        .clipped()
        .task { await viewModel.load() }
        .accessibilityHidden(true)
    }
}
