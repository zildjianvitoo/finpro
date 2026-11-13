//
//  RecordProgressButton.swift
//  finpro
//
//  The record button of the recording screen, in the style of a short-video camera: a red disc
//  to start or resume, and a translucent disc of the same size with a red rounded square while recording.
//  A red ring on the edge of the button fills with the progress through the song, with a white mark at the start
//  of every segment and at the end of the filled part.
//

import SwiftUI

struct RecordProgressButton: View {
    enum Mode {
        /// Ready or paused: the red disc starts or resumes.
        case idle
        /// Recording: the red square pauses.
        case recording
    }

    let mode: Mode
    /// Share of the song sung so far, 0...1; read every frame.
    let progress: () -> Double
    /// Share of the song at which each segment after the first starts.
    let boundaries: [Double]
    let action: () -> Void

    private let idleDiameter: CGFloat = 80
    private let recordingDiameter: CGFloat = 80
    private let ringWidth: CGFloat = 6
    /// Width of the grey ring around the red disc when idle; the red progress ring sits on its edge.
    private let idleRingWidth: CGFloat = 12
    private let idleCoreDiameter: CGFloat = 54
    private let recordingCoreSide: CGFloat = 32
    private let squareCornerRadius: CGFloat = 8
    private let markWidth: CGFloat = 2
    private let discOpacity = 0.4
    private let refreshInterval: TimeInterval = 1.0 / 30

    var body: some View {
        Button(action: action) {
            ZStack {
                // Translucent base, as big as the button: a ring around the red disc, or a full disc
                // around the square. The red progress ring is drawn on its edge, inside the button.
                Circle()
                    .fill(.white.opacity(mode == .recording ? discOpacity : 0))
                Circle()
                    .strokeBorder(.white.opacity(mode == .recording ? 0 : discOpacity), lineWidth: idleRingWidth)

                RoundedRectangle(cornerRadius: mode == .recording ? squareCornerRadius : idleCoreDiameter / 2, style: .continuous)
                    .fill(Color.recordRed)
                    .frame(width: mode == .recording ? recordingCoreSide : idleCoreDiameter,
                           height: mode == .recording ? recordingCoreSide : idleCoreDiameter)

                TimelineView(.animation(minimumInterval: refreshInterval)) { _ in
                    Canvas { context, size in
                        drawRing(in: &context, size: size, progress: min(max(progress(), 0), 1))
                    }
                }
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
            .animation(.snappy(duration: 0.3), value: mode)
        }
        .buttonStyle(.plain)
    }

    private var diameter: CGFloat { mode == .recording ? recordingDiameter : idleDiameter }

    private func drawRing(in context: inout GraphicsContext, size: CGSize, progress: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = (min(size.width, size.height) - ringWidth) / 2
        func angle(_ share: Double) -> Angle { .degrees(-90 + 360 * share) }

        if progress > 0 {
            var arc = Path()
            arc.addArc(center: center, radius: radius, startAngle: angle(0), endAngle: angle(progress), clockwise: false)
            context.stroke(arc, with: .color(Color.recordRed), style: StrokeStyle(lineWidth: ringWidth, lineCap: .butt))
        }

        // White marks across the ring: the start of every segment, and the end of the filled part.
        let marks = boundaries.filter { $0 > 0 && $0 < 1 } + (progress > 0 && progress < 1 ? [progress] : [])
        for share in marks {
            let direction = CGPoint(x: cos(angle(share).radians), y: sin(angle(share).radians))
            var mark = Path()
            mark.move(to: CGPoint(x: center.x + direction.x * (radius - ringWidth / 2 - 1),
                                  y: center.y + direction.y * (radius - ringWidth / 2 - 1)))
            mark.addLine(to: CGPoint(x: center.x + direction.x * (radius + ringWidth / 2 + 1),
                                     y: center.y + direction.y * (radius + ringWidth / 2 + 1)))
            context.stroke(mark, with: .color(.white), style: StrokeStyle(lineWidth: markWidth, lineCap: .butt))
        }
    }
}
