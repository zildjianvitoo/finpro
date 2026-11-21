//
//  AppTypography.swift
//  finpro
//

import SwiftUI
import UIKit

/// Display typography from the v2 artboard. All measurements use the same SF Pro weight as Font.appDisplay.
enum AppTypography {
    static let vocalDisplaySize: CGFloat = 80

    static func fittedVocalDisplaySize(width: CGFloat) -> CGFloat {
        let font = UIFont.systemFont(ofSize: vocalDisplaySize, weight: .bold)
        let widest = ["First,", "Meet", "Your", "vocal", "range"].map {
            ($0 as NSString).size(withAttributes: [.font: font]).width
        }.max() ?? width
        return vocalDisplaySize * min(1, max(1, width) / max(1, widest))
    }
    /// The stacked words touch at their cap-height rhythm, rather than using three full text line boxes.
    static func vocalDisplayLineAdvance(size: CGFloat) -> CGFloat {
        UIFont.systemFont(ofSize: size, weight: .bold).capHeight
    }
    /// Space between the stacked words' frame and their ink: above the cap height of the first
    /// word (positive) and the descenders hanging below the last word's frame (negative), so the
    /// block can be laid out by what is drawn.
    static func vocalDisplayInkInsets(size: CGFloat) -> (top: CGFloat, bottom: CGFloat) {
        let font = UIFont.systemFont(ofSize: size, weight: .bold)
        return (font.ascender - font.capHeight, font.capHeight - font.ascender + font.descender)
    }
}
