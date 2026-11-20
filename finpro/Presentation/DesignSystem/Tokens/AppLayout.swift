//
//  AppLayout.swift
//  finpro
//

import SwiftUI

enum AppLayout {
    static let buttonHeight: CGFloat = 56
    static let iconButton: CGFloat = 44
    static let microphoneDiameter: CGFloat = 170
    static let importSheetHeight: CGFloat = 440
    static let clipSheetHeight: CGFloat = 490
    static let songSectionSheetHeight: CGFloat = 362
    /// Opacity of the plum loading overlay (`Color.loadingOverlay`) over a screen.
    static let loadingOverlayOpacity: Double = 0.55
    /// Over busy content right behind the loading text (the clip sheet while preparing a song).
    static let loadingOverlayOpacityBusy: Double = 0.7
    /// Loading mascot inside a sheet section (lyrics search).
    static let loadingMascotCompact: CGFloat = 120
    /// Loading mascot next to a line of text (preparing a key).
    static let loadingMascotInline: CGFloat = 44
    static let dialHeight: CGFloat = 180
}
