//
//  SpeechBubbleShape.swift
//  finpro
//

import SwiftUI

struct SpeechBubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: rect.maxX, y: 0))
        path.addCurve(to: CGPoint(x: rect.width * 0.67, y: rect.height * 0.91),
                      control1: CGPoint(x: rect.maxX, y: rect.height * 0.55),
                      control2: CGPoint(x: rect.width * 0.88, y: rect.height * 0.76))
        path.addLine(to: CGPoint(x: rect.width * 0.60, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.width * 0.56, y: rect.height * 0.93))
        path.addQuadCurve(to: CGPoint(x: 0, y: rect.height * 0.87),
                         control: CGPoint(x: rect.width * 0.27, y: rect.height * 1.02))
        path.closeSubpath()
        return path
    }
}
