//
//  Color+Light.swift
//  finpro
//
//  A token's light-mode colour in both modes, for things drawn on a surface that does not change
//  in dark mode (ticks on the lime band, a badge on a video thumbnail).
//

import SwiftUI

extension Color {
    var lightResolved: Color {
        var environment = EnvironmentValues()
        environment.colorScheme = .light
        return Color(resolve(in: environment))
    }
}
