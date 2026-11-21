//
//  CurvedPitchDial.swift
//  finpro
//

import SwiftUI

/// Key dial (design 4.5, revision 2026-11-21): semitone ticks stand on the top of a large circle,
/// pointing at its centre, with the key names along the arc. The arc turns under a fixed centre
/// marker; about five keys show at once and the ends fade out.
struct CurvedPitchDial: View, Animatable {
    var value: Double
    var center: Double
    var bounds: ClosedRange<Int> = -6...6
    var label: (Double) -> String

    /// Angle between two semitones on the arc.
    static let semitoneAngle = 21.0
    /// The arc is the top of the light backdrop circle behind the dial (same centre and radius),
    /// so the ticks stand on its edge.
    private static let radiusRatio: CGFloat = AppLayout.keyDialBackdropScale / 2
    /// Ticks and labels fade out between these angles (the side edges are at about 53°).
    private static let fadeAngles = 38.0...56.0
    private static let ticksPerSemitone = 6
    /// Space above the arc's top for the labels (the backdrop circle starts there).
    private static let labelSpace: CGFloat = AppLayout.keyDialBackdropTop
    private static let labelOutset: CGFloat = 26
    /// Tick lengths, pointing inward from the arc.
    private static let selectedLength: CGFloat = 112
    private static let majorLength: CGFloat = 84
    private static let minorLength: CGFloat = 58

    static let height: CGFloat = 250
    /// Distance between two semitones along the arc, as a fraction of the dial's width (for drags).
    static let noteSpacingRatio: CGFloat = radiusRatio * (semitoneAngle * .pi / 180)

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(value, center) }
        set { value = newValue.first; center = newValue.second }
    }

    /// Radius of the arc and its centre for a dial `width` wide.
    private static func circle(width: CGFloat) -> (center: CGPoint, radius: CGFloat) {
        let radius = width * radiusRatio
        return (CGPoint(x: width / 2, y: labelSpace + radius), radius)
    }

    /// Where a key's label sits (and how it is turned) when it is `offset` semitones from the
    /// middle, `outset` points further out than the label. Used to place the Recommended badge.
    static func labelAnchor(offset: Double, width: CGFloat, outset: CGFloat = 0) -> (point: CGPoint, angle: Angle, opacity: Double) {
        let degrees = offset * semitoneAngle
        let (c, r) = circle(width: width)
        let distance = r + labelOutset + outset
        let theta = degrees * .pi / 180
        return (CGPoint(x: c.x + distance * sin(theta), y: c.y - distance * cos(theta)), .degrees(degrees), fade(degrees))
    }

    private static func fade(_ degrees: Double) -> Double {
        let angle = abs(degrees)
        return max(0, min(1, 1 - (angle - fadeAngles.lowerBound) / (fadeAngles.upperBound - fadeAngles.lowerBound)))
    }

    private var visibleNotes: ClosedRange<Int> {
        let reach = Int(ceil(Self.fadeAngles.upperBound / Self.semitoneAngle))
        let start = max(bounds.lowerBound, Int(floor(center)) - reach)
        let end = min(bounds.upperBound, Int(ceil(center)) + reach)
        return start...max(start, end)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let (c, r) = Self.circle(width: width)
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    let ticks = Self.ticksPerSemitone
                    for tick in (visibleNotes.lowerBound * ticks)...(visibleNotes.upperBound * ticks) {
                        let note = Double(tick) / Double(ticks)
                        let degrees = (note - center) * Self.semitoneAngle
                        let opacity = Self.fade(degrees)
                        guard opacity > 0 else { continue }
                        let major = tick.isMultiple(of: ticks)
                        // Only the tick under the marker is drawn long, so a dial between two keys
                        // (while dragged) shows one marker.
                        if major, abs(note - value) < 0.05 { continue }
                        let length = major ? Self.majorLength : Self.minorLength
                        let width: CGFloat = major ? 6 : 4
                        var local = context
                        local.opacity = opacity
                        local.translateBy(x: c.x, y: c.y)
                        local.rotate(by: .degrees(degrees))
                        let rect = CGRect(x: -width / 2, y: -r, width: width, height: length)
                        local.fill(Path(roundedRect: rect, cornerRadius: width / 2),
                                   with: .color(Color.primaryBrand.opacity(major ? 0.6 : 0.4)))
                    }
                    // The marker: the selected key, or the dial's position while dragged.
                    var marker = context
                    marker.translateBy(x: c.x, y: c.y)
                    marker.rotate(by: .degrees((value - center) * Self.semitoneAngle))
                    marker.fill(Path(roundedRect: CGRect(x: -3, y: -r, width: 6, height: Self.selectedLength), cornerRadius: 3),
                                with: .color(.primaryBrand))
                }
                ForEach(Array(visibleNotes), id: \.self) { note in
                    let anchor = Self.labelAnchor(offset: Double(note) - center, width: width)
                    Text(label(Double(note)))
                        .font(.appTitle1.weight(.bold))
                        .foregroundStyle(note == Int(value.rounded()) ? Color.primaryBrand : Color.primary300)
                        .fixedSize()
                        .rotationEffect(anchor.angle)
                        .opacity(anchor.opacity)
                        .position(anchor.point)
                }
            }
        }
        .frame(height: Self.height)
    }
}
