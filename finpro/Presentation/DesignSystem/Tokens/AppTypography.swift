//
//  AppTypography.swift
//  finpro
//

import SwiftUI
import UIKit

/// Display typography from the v2 artboard. All measurements use the same SF Pro weight as Font.appDisplay.
enum AppTypography {
    static let vocalDisplaySize: CGFloat = 76

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
}
