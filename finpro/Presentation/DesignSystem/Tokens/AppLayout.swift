//
//  AppLayout.swift
//  finpro
//

import SwiftUI

enum AppLayout {
    static let buttonHeight: CGFloat = 56
    static let iconButton: CGFloat = 44
    /// Text pill next to the 44 pt icon buttons in a header (Select on Song List).
    static let headerPillHeight: CGFloat = 40
    /// The vocal test's microphone button, halo included (draft 2.5b).
    static let microphoneDiameter: CGFloat = 140
    static let importSheetHeight: CGFloat = 425
    static let clipSheetHeight: CGFloat = 466
    /// Opacity of the plum loading overlay (`Color.loadingOverlay`) over a screen.
    static let loadingOverlayOpacity: Double = 0.55
    /// Over busy content right behind the loading text (the clip sheet while preparing a song).
    static let loadingOverlayOpacityBusy: Double = 0.7
    /// Loading mascot inside a sheet section (lyrics search).
    static let loadingMascotCompact: CGFloat = 120
    /// Loading mascot next to a line of text (preparing a key).
    static let loadingMascotInline: CGFloat = 44
    /// Light circle behind the key dial: its diameter as a multiple of the dial's width and its
    /// top below the dial's top (design 4.5).
    static let keyDialBackdropScale: CGFloat = 1.25
    static let keyDialBackdropTop: CGFloat = 52
    /// Space between the Find Your Key subtitle and the dial (the dial sits mid-screen).
    static let keyDialTop: CGFloat = 153
}
