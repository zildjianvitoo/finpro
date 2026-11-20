//
//  Font+Typography.swift
//  finpro
//
//  Typography scale of the design system (Sketch page "Design System", "Typography Scale").
//  Built on the system text styles, so sizes follow Dynamic Type; at the default size they are
//  the Sketch sizes: Large Title 34, Title 1 28, Title 2 22, Title 3 20, Headline/Body/CTA 17,
//  Subheadline 15, Footnote 13, Caption 12, Caption 2 11.
//

import SwiftUI

extension Font {
    /// SF Pro display lettering used by the vocal intro.
    static func appDisplay(size: CGFloat) -> Font { .system(size: size, weight: .bold) }
    /// Large Title / Bold / 34
    static var appLargeTitle: Font { .largeTitle.weight(.bold) }
    /// Title 1 / SemiBold / 28
    static var appTitle1: Font { .title.weight(.semibold) }
    /// Title 2 / SemiBold / 22
    static var appTitle2: Font { .title2.weight(.semibold) }
    /// Title 3 / Regular / 20
    static var appTitle3: Font { .title3 }
    /// Headline / SemiBold / 17
    static var appHeadline: Font { .headline }
    /// Body / Regular / 17
    static var appBody: Font { .body }
    /// Subheadline / Regular / 15
    static var appSubheadline: Font { .subheadline }
    /// Footnote / Regular / 13
    static var appFootnote: Font { .footnote }
    /// Caption / Regular / 12
    static var appCaption: Font { .caption }
    /// Caption 2 / Regular / 11
    static var appCaption2: Font { .caption2 }
    /// Button / CTA / SemiBold / 17
    static var appCTA: Font { .body.weight(.semibold) }
}
