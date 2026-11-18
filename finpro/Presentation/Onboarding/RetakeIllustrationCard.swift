//
//  RetakeIllustrationCard.swift
//  finpro
//
//  The clips card of onboarding page 2, drawn natively: three clip waveforms, a scrub line
//  playing through the first with its running time, the middle clip marked for a retake whose
//  icon turns once per loop, and the last clip dimmed up to its handle. Laid out in the
//  illustration's pixels (docs/illustrations/ob2-full.png), scaled by `unit`.
//

import SwiftUI

struct RetakeIllustrationCard: View {
    /// Seconds since the animation started; 0 shows the resting frame.
    let time: TimeInterval
    /// View points per illustration pixel.
    let unit: CGFloat

    /// Card size in illustration pixels.
    static let size = CGSize(width: 614, height: 632)

    private static let loop: TimeInterval = 6
    /// Scrub line: where it sweeps between, and the time it shows at `designScrubX` (the design's 0:59.7).
    private static let scrubRange: ClosedRange<CGFloat> = 120...500
    private static let designScrubX: CGFloat = 312
    private static let designScrubSeconds: TimeInterval = 59.7
    private static let secondsPerPixel: TimeInterval = 0.02
    /// The retake icon turns during this part of the loop.
    private static let spinStart: TimeInterval = 3.6
    private static let spinDuration: TimeInterval = 0.7

    // Layout in illustration pixels.
    private static let cornerRadius: CGFloat = 30
    private static let rowX: CGFloat = 42
    private static let rowWidth: CGFloat = 540
    private static let rowHeight: CGFloat = 150
    private static let rowTops: [CGFloat] = [58, 228, 408]
    private static let rowRadius: CGFloat = 26
    private static let barStartX: CGFloat = 62
    private static let barStep: CGFloat = 24.5
    private static let barWidth: CGFloat = 11
    private static let barMaxHeight: CGFloat = 124
    private static let barHeights: [CGFloat] = [0.18, 0.32, 0.56, 0.24, 0.42, 0.3, 0.5, 0.78, 0.46, 0.96, 0.36, 0.7,
                                                1.0, 0.5, 0.84, 0.28, 0.74, 0.46, 0.32, 0.56, 0.28, 0.2]
    /// Light marker line across the first and last clips.
    private static let markerX: CGFloat = 360
    private static let retakeWindow: ClosedRange<CGFloat> = 208...400
    private static let retakeSelection: ClosedRange<CGFloat> = 292...345
    private static let dimmedEnd: CGFloat = 258
    private static let handleWidth: CGFloat = 16
    private static let footerY: CGFloat = 590

    private static let bar = Color.white.opacity(0.55)

    var body: some View {
        Canvas { context, _ in draw(in: &context) }
            .frame(width: Self.size.width * unit, height: Self.size.height * unit)
            .background(Color.primaryBrand)
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius * unit, style: .continuous))
    }

    private func draw(in context: inout GraphicsContext) {
        let now = time == 0 ? 0 : time.truncatingRemainder(dividingBy: Self.loop)
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: x * unit, y: y * unit, width: w * unit, height: h * unit)
        }

        for (index, top) in Self.rowTops.enumerated() {
            let row = rect(Self.rowX, top, Self.rowWidth, Self.rowHeight)
            let shape = Path(roundedRect: row, cornerRadius: Self.rowRadius * unit, style: .continuous)
            context.fill(shape, with: .color(.trimmerTrack))
            var clip = context
            clip.clip(to: shape)
            // Waveform bars, with the middle row's retake window and the last row's dimmed start.
            for (bar, height) in Self.barHeights.enumerated() {
                let x = Self.barStartX + CGFloat(bar) * Self.barStep
                let h = Self.barMaxHeight * height
                clip.fill(Path(roundedRect: rect(x, top + (Self.rowHeight - h) / 2, Self.barWidth, h),
                               cornerRadius: Self.barWidth / 2 * unit), with: .color(Self.bar))
            }
            switch index {
            case 1:
                let window = Self.retakeWindow, selection = Self.retakeSelection
                let pulse = time == 0 ? 0 : (sin(now / Self.loop * 2 * .pi) + 1) / 2
                clip.fill(Path(rect(window.lowerBound, top, window.upperBound - window.lowerBound, Self.rowHeight)),
                          with: .color(.trimmerSelection.opacity(0.75 + 0.15 * pulse)))
                clip.fill(Path(rect(selection.lowerBound, top, selection.upperBound - selection.lowerBound, Self.rowHeight)),
                          with: .color(.plumNight))
                drawRetakeIcon(in: &context, centre: CGPoint(x: (selection.lowerBound + selection.upperBound) / 2 * unit,
                                                              y: (top + Self.rowHeight / 2) * unit), now: now)
            case 2:
                clip.fill(Path(rect(Self.rowX, top, Self.dimmedEnd - Self.rowX, Self.rowHeight)), with: .color(.trimmerSelection.opacity(0.85)))
                drawHandle(in: &clip, x: Self.dimmedEnd - Self.handleWidth, top: top + 22, height: Self.rowHeight - 44)
                drawMarker(in: &clip, top: top)
            default:
                drawMarker(in: &clip, top: top)
            }
        }

        // Scrub line through the first clip, with its time above and a knob on the last clip.
        let scrubX = scrubPosition(at: now)
        let firstTop = Self.rowTops[0]
        var line = Path()
        line.move(to: CGPoint(x: scrubX * unit, y: firstTop * unit))
        line.addLine(to: CGPoint(x: scrubX * unit, y: (firstTop + Self.rowHeight) * unit))
        context.stroke(line, with: .color(.plumNight), lineWidth: 4 * unit)
        context.fill(Path(ellipseIn: rect(scrubX - 8, firstTop - 8, 16, 18)), with: .color(.plumNight))
        drawHandle(in: &context, x: scrubX - Self.handleWidth / 2, top: firstTop + 22, height: Self.rowHeight - 44)
        let seconds = Self.designScrubSeconds + Double(scrubX - Self.designScrubX) * Self.secondsPerPixel
        let label = Text(String(format: "%d:%04.1f", Int(seconds) / 60, seconds.truncatingRemainder(dividingBy: 60)))
            .font(.system(size: 22 * unit, weight: .medium).monospacedDigit()).foregroundStyle(.white)
        let chip = rect(scrubX - 40, firstTop - 40, 80, 34)
        context.fill(Path(roundedRect: chip, cornerRadius: 10 * unit), with: .color(.plumNight))
        context.draw(label, at: CGPoint(x: chip.midX, y: chip.midY))
        let lastTop = Self.rowTops[2]
        var lower = Path()
        lower.move(to: CGPoint(x: Self.designScrubX * unit, y: lastTop * unit))
        lower.addLine(to: CGPoint(x: Self.designScrubX * unit, y: (lastTop + Self.rowHeight) * unit))
        context.stroke(lower, with: .color(.plumNight), lineWidth: 4 * unit)
        context.fill(Path(ellipseIn: rect(Self.designScrubX - 8, lastTop - 8, 16, 18)), with: .color(.plumNight))

        // Footer: the selected part of the song.
        let font = Font.system(size: 24 * unit, weight: .medium)
        context.draw(Text("0:59").font(font).foregroundStyle(.white), at: CGPoint(x: 48 * unit, y: Self.footerY * unit), anchor: .leading)
        context.draw(Text("1m 42s selected").font(font).foregroundStyle(.white),
                     at: CGPoint(x: Self.size.width / 2 * unit, y: Self.footerY * unit))
        context.draw(Text("3:14").font(font).foregroundStyle(.white),
                     at: CGPoint(x: (Self.size.width - 40) * unit, y: Self.footerY * unit), anchor: .trailing)
    }

    /// Sweeps right and back once per loop, easing at the ends; the design spot when resting.
    private func scrubPosition(at now: TimeInterval) -> CGFloat {
        guard time != 0 else { return Self.designScrubX }
        let phase = (1 - cos(now / Self.loop * 2 * .pi)) / 2
        return Self.scrubRange.lowerBound + (Self.scrubRange.upperBound - Self.scrubRange.lowerBound) * CGFloat(phase)
    }

    private func drawRetakeIcon(in context: inout GraphicsContext, centre: CGPoint, now: TimeInterval) {
        let progress = min(max((now - Self.spinStart) / Self.spinDuration, 0), 1)
        let eased = progress * progress * (3 - 2 * progress)
        var icon = context
        icon.translateBy(x: centre.x, y: centre.y)
        icon.rotate(by: .degrees(360 * eased))
        icon.draw(Text(Image(systemName: "repeat")).font(.system(size: 40 * unit, weight: .semibold)).foregroundStyle(.white),
                  at: .zero)
    }

    private func drawHandle(in context: inout GraphicsContext, x: CGFloat, top: CGFloat, height: CGFloat) {
        let handle = CGRect(x: x * unit, y: top * unit, width: Self.handleWidth * unit, height: height * unit)
        context.fill(Path(roundedRect: handle, cornerRadius: 6 * unit), with: .color(.plumNight))
        var grip = Path()
        grip.move(to: CGPoint(x: handle.midX, y: handle.minY + 18 * unit))
        grip.addLine(to: CGPoint(x: handle.midX, y: handle.maxY - 18 * unit))
        context.stroke(grip, with: .color(.white), lineWidth: 3 * unit)
    }

    private func drawMarker(in context: inout GraphicsContext, top: CGFloat) {
        context.fill(Path(CGRect(x: (Self.markerX - 5) * unit, y: top * unit, width: 10 * unit, height: Self.rowHeight * unit)),
                     with: .color(.white.opacity(0.75)))
    }
}
