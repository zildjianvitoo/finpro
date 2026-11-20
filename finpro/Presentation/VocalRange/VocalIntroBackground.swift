//
//  VocalIntroBackground.swift
//  finpro
//

import SwiftUI

/// Curved at the top and solid to the bottom; unlike an ellipse, it cannot expose the home-indicator area.
struct VocalIntroBackground: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height * 0.2))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.height * 0.2),
                          control: CGPoint(x: rect.midX, y: -rect.height * 0.2))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: 0, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
