//
//  ExportProgressBorder.swift
//  finpro
//
//  The export progress of 7.2, drawn as a border around the video (like CapCut): a dark track
//  with a lime part that grows clockwise from the top centre. Owner: Zildjian Vito (ZV-13).
//

import SwiftUI

struct ExportProgressBorder: View {
    /// 0...1
    let progress: Double
    var lineWidth: CGFloat = 10
    var cornerRadius: CGFloat = 24

    var body: some View {
        let shape = BorderPath(cornerRadius: cornerRadius)
        ZStack {
            shape.stroke(Color.exportTrack, lineWidth: lineWidth)
            shape.trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(Color.secBrand, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
        .padding(lineWidth / 2)
        .accessibilityElement()
        .accessibilityLabel("Export progress")
        .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
    }

    /// A rounded rectangle that starts at the top centre and runs clockwise, so `trim` grows from there.
    private struct BorderPath: Shape {
        let cornerRadius: CGFloat

        func path(in rect: CGRect) -> Path {
            let r = min(cornerRadius, rect.width / 2, rect.height / 2)
            var path = Path()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r,
                        startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r,
                        startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r,
                        startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r,
                        startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
            path.closeSubpath()
            return path
        }
    }
}

#Preview {
    ExportProgressBorder(progress: 0.58)
        .frame(width: 288, height: 453)
}
