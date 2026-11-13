//
//  VocalResultHeaderShape.swift
//  finpro
//

import SwiftUI

struct VocalResultHeaderShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: rect.maxX, y: 0))
        path.addCurve(to: CGPoint(x: 0, y: rect.height * 0.86),
                      control1: CGPoint(x: rect.maxX, y: rect.height * 1.08),
                      control2: CGPoint(x: rect.width * 0.4, y: rect.height * 1.22))
        path.closeSubpath()
        return path
    }
}
