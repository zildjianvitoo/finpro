//
//  CurvedPitchDial.swift
//  finpro
//

import SwiftUI

/// Ordered semitone ticks move under a fixed center reference. No time-based pitch animation is used.
struct CurvedPitchDial: View, Animatable {
    var value: Double
    var center: Double
    var bounds: ClosedRange<Int> = -6...6
    var hasSignal = true
    var highlightsPitch = false
    var label: (Double) -> String

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(value, center) }
        set { value = newValue.first; center = newValue.second }
    }
    private var visibleNotes: ClosedRange<Int> {
        let start = max(bounds.lowerBound, Int(floor(center)) - 3)
        let end = min(bounds.upperBound, Int(ceil(center)) + 3)
        return start...max(start, end)
    }
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let noteSpacing = width * 0.26
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    for tick in (visibleNotes.lowerBound * 6)...(visibleNotes.upperBound * 6) {
                        let note = Double(tick) / 6
                        let x = size.width / 2 + (note - center) * noteSpacing
                        guard x >= -20, x <= size.width + 20 else { continue }
                        let fraction = (x - size.width / 2) / max(1, size.width / 2)
                        let major = tick.isMultiple(of: 6)
                        let selected = major && tick / 6 == Int(value.rounded())
                        let y = 48 + fraction * fraction * 28
                        let height: Double = selected ? 112 : major ? 88 : 64
                        var local = context
                        local.translateBy(x: x, y: y + height / 2)
                        local.rotate(by: .degrees(-fraction * 28))
                        let rect = CGRect(x: selected ? -3 : -2, y: -height / 2,
                                          width: selected ? 6 : 4, height: height)
                        let tint = Color.primaryBrand.opacity(selected ? 1 : 0.55)
                        local.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(tint))
                    }
                    // The center always represents the actual continuous pitch / selected key.
                    let playheadX = size.width / 2 + (value - center) * noteSpacing
                    let marker = CGRect(x: playheadX - 2, y: 48, width: 4, height: 112)
                    context.fill(Path(roundedRect: marker, cornerRadius: 2),
                                 with: .color(highlightsPitch && hasSignal ? .secBrand : .primaryBrand))
                }
                ForEach(Array(visibleNotes), id: \.self) { note in
                    let x = width / 2 + CGFloat(Double(note) - center) * noteSpacing
                    let fraction = abs((x - width / 2) / max(1, width / 2))
                    Text(label(Double(note)))
                        .font(.appTitle1)
                        .foregroundStyle(Color.primaryBrand.opacity(note == Int(value.rounded()) ? 1 : 0.65))
                        .fixedSize()
                        .position(x: x, y: 20 + fraction * 16)
                }
            }
        }
        .frame(height: AppLayout.dialHeight)
        .mask {
            LinearGradient(stops: [.init(color: .clear, location: 0),
                                   .init(color: .black, location: 0.14),
                                   .init(color: .black, location: 0.86),
                                   .init(color: .clear, location: 1)],
                           startPoint: .leading, endPoint: .trailing)
        }
        .clipped()
    }
}
