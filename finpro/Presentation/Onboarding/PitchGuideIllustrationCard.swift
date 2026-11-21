//
//  PitchGuideIllustrationCard.swift
//  finpro
//
//  The pitch guide card of onboarding page 1, drawn natively so it matches the latest pitch guide:
//  word notes scroll past the playhead with centred labels, the lime voice dot follows the melody
//  and sparkles while on pitch, the part being sung sweeps grey, and each finished bar turns full
//  green (on pitch) or full red (off pitch — never half red, half green). Laid out in the
//  illustration's pixels (docs/illustrations/ob1-full.png), scaled by `unit`.
//

import SwiftUI

struct PitchGuideIllustrationCard: View {
    /// Seconds since the animation started; 0 shows the resting frame.
    let time: TimeInterval
    /// View points per illustration pixel.
    let unit: CGFloat

    /// Card size in illustration pixels (before its tilt).
    static let size = CGSize(width: 692, height: 639)

    private struct Note {
        let word: String
        let row: Int
        let start: TimeInterval
        let end: TimeInterval
        /// Sung off pitch for the whole note (dot sits below the bar, no sparkle, full red once passed).
        var isMissed = false
    }

    private static let rowNames = ["C4", "B3", "A3", "G3", "F3", "E3", "D3"]
    private static let lines = ["A whole new world", "A hundred thousand things to see"]
    /// One loop of the melody; the second line starts at `secondLineStart`.
    private static let notes: [Note] = [
        Note(word: "A", row: 4, start: 0.0, end: 0.6),
        Note(word: "whole", row: 3, start: 0.8, end: 1.7, isMissed: true),
        Note(word: "new", row: 1, start: 1.9, end: 2.6),
        Note(word: "world", row: 2, start: 2.8, end: 3.9),
        Note(word: "A", row: 4, start: 4.6, end: 5.0),
        Note(word: "hundred", row: 2, start: 5.2, end: 5.9),
        Note(word: "thousand", row: 1, start: 6.1, end: 6.9),
        Note(word: "things", row: 2, start: 7.1, end: 7.6),
        Note(word: "to", row: 3, start: 7.8, end: 8.2),
        Note(word: "see", row: 4, start: 8.4, end: 9.4),
    ]
    private static let loop: TimeInterval = 10.2
    private static let secondLineStart: TimeInterval = 4.3
    /// Resting frame (Reduce Motion): "whole" full red, "new" mid-sing with the lime dot sparkling.
    private static let restingTime: TimeInterval = 2.25

    // Layout in illustration pixels.
    private static let cornerRadius: CGFloat = 56
    private static let labelX: CGFloat = 66
    private static let laneStart: CGFloat = 108
    private static let laneEnd: CGFloat = 664
    private static let firstRowY: CGFloat = 100
    private static let rowStep: CGFloat = 60
    private static let playheadX: CGFloat = 268
    private static let playheadTop: CGFloat = 66
    private static let playheadBottom: CGFloat = 512
    private static let pointsPerSecond: CGFloat = 150
    private static let noteHeight: CGFloat = 42
    private static let dotSize: CGFloat = 50
    private static let lyricsY: CGFloat = 556
    private static let lyricsStep: CGFloat = 50

    // Colours matching the frosted card and the latest PianoRollView palette.
    private static let cardCentre = Color(red: 146 / 255, green: 89 / 255, blue: 130 / 255)
    private static let cardEdge = Color(red: 206 / 255, green: 181 / 255, blue: 199 / 255)
    private static let rowLine = Color.white.opacity(0.45)
    private static let playhead = Color.primary800
    private static let noteFill = Color.secondaryButton
    private static let passedNoteFill = Color.gray
    private static let voiceDot = Color.secBrand

    var body: some View {
        Canvas { context, _ in draw(in: &context) }
            .frame(width: Self.size.width * unit, height: Self.size.height * unit)
            .background(
                RadialGradient(colors: [Self.cardCentre, Self.cardEdge], center: .center,
                               startRadius: 0, endRadius: Self.size.width * 0.62 * unit)
                    .opacity(0.94)
            )
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius * unit, style: .continuous))
            .environment(\.colorScheme, .light)
    }

    private func draw(in context: inout GraphicsContext) {
        let now = (time == 0 ? Self.restingTime : time).truncatingRemainder(dividingBy: Self.loop)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * unit, y: y * unit) }
        func rowY(_ row: Double) -> CGFloat { Self.firstRowY + CGFloat(row) * Self.rowStep }

        // Rows with their note names.
        for (index, name) in Self.rowNames.enumerated() {
            let y = rowY(Double(index))
            context.draw(Text(name).font(.system(size: 24 * unit, weight: .medium)).foregroundStyle(.white.opacity(0.85)),
                         at: point(Self.labelX, y))
            var line = Path()
            line.move(to: point(Self.laneStart, y))
            line.addLine(to: point(Self.laneEnd, y))
            context.stroke(line, with: .color(Self.rowLine), lineWidth: 8 * unit)
        }

        // Notes: this loop and the next, so the melody keeps coming in from the right.
        var lane = context
        lane.clip(to: Path(CGRect(origin: point(Self.laneStart - Self.noteHeight / 2, 0),
                                  size: CGSize(width: (Self.laneEnd - Self.laneStart + Self.noteHeight) * unit,
                                               height: Self.size.height * unit))))
        for repeatShift in [-Self.loop, 0, Self.loop] {
            for note in Self.notes {
                let start = note.start + repeatShift, end = note.end + repeatShift
                let x0 = Self.playheadX + CGFloat(start - now) * Self.pointsPerSecond
                let x1 = Self.playheadX + CGFloat(end - now) * Self.pointsPerSecond
                guard x1 > Self.laneStart - Self.noteHeight, x0 < Self.laneEnd + Self.noteHeight else { continue }
                let y = rowY(Double(note.row))
                let width = max(Self.noteHeight, x1 - x0)
                let rect = CGRect(x: x0 * unit, y: (y - Self.noteHeight / 2) * unit,
                                  width: width * unit, height: Self.noteHeight * unit)
                let shape = Path(roundedRect: rect, cornerRadius: rect.height / 2)

                if end <= now {
                    // Finished bar: whole bar turns solid green (on pitch) or solid red (missed).
                    lane.fill(shape, with: .color(note.isMissed ? .noteMiss : .pitchHit))
                } else {
                    // Upcoming or currently singing: light bar whose passed part sweeps grey, like live recording.
                    lane.fill(shape, with: .color(Self.noteFill))
                    let passed = min(x0 + width, Self.playheadX)
                    if passed > x0 {
                        var sung = lane
                        sung.clip(to: shape)
                        sung.fill(Path(CGRect(x: x0 * unit, y: rect.minY,
                                              width: (passed - x0) * unit, height: rect.height)),
                                  with: .color(Self.passedNoteFill))
                    }
                }

                // Word label centred directly under the bar, matching PianoRollView.
                lane.draw(Text(note.word).font(.system(size: 24 * unit, weight: .medium)).foregroundStyle(.white),
                          at: CGPoint(x: rect.midX, y: rect.maxY + 4 * unit), anchor: .top)
            }
        }

        // Playhead, and the lime voice dot at the pitch being sung (sparkling while on pitch).
        var playhead = Path()
        playhead.move(to: point(Self.playheadX, Self.playheadTop))
        playhead.addLine(to: point(Self.playheadX, Self.playheadBottom))
        context.stroke(playhead, with: .color(Self.playhead), lineWidth: 10 * unit)

        let voice = voiceState(at: now)
        let center = point(Self.playheadX, rowY(voice.row))
        let radius = Self.dotSize / 2 * unit
        if voice.onPitch {
            sparkle(around: center, radius: radius, at: now, in: &context)
        }
        let dot = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: dot), with: .color(Self.voiceDot.opacity(voice.singing ? 1 : 0.7)))

        // Lyrics: the line being sung, then the next one.
        let current = now < Self.secondLineStart ? 0 : 1
        for (offset, index) in [current, 1 - current].enumerated() {
            context.draw(Text(Self.lines[index]).font(.system(size: 34 * unit, weight: offset == 0 ? .semibold : .regular))
                            .foregroundStyle(.white.opacity(offset == 0 ? 1 : 0.75)),
                         at: point(Self.size.width / 2, Self.lyricsY + CGFloat(offset) * Self.lyricsStep))
        }
    }

    /// Matching `PianoRollView.sparkle`: pulsing lime glow, expanding rings, and bursting stars.
    private func sparkle(around center: CGPoint, radius: CGFloat, at now: TimeInterval, in context: inout GraphicsContext) {
        let pulse = 0.5 + 0.5 * sin(now * 2 * .pi * 2.5)
        var glow = context
        glow.addFilter(.blur(radius: radius * 1.1))
        let glowRadius = radius * (1.9 + 0.45 * pulse)
        glow.fill(Path(ellipseIn: CGRect(x: center.x - glowRadius, y: center.y - glowRadius,
                                         width: glowRadius * 2, height: glowRadius * 2)),
                  with: .color(Self.voiceDot.opacity(0.45 + 0.3 * pulse)))

        for offset in [0.0, 0.5] {
            let progress = (now / 0.7 + offset).truncatingRemainder(dividingBy: 1)
            let ringRadius = radius * (1.1 + 1.8 * progress)
            context.stroke(Path(ellipseIn: CGRect(x: center.x - ringRadius, y: center.y - ringRadius,
                                                  width: ringRadius * 2, height: ringRadius * 2)),
                           with: .color(Self.voiceDot.opacity(0.8 * (1 - progress))),
                           lineWidth: max(1, radius * 0.22 * (1 - progress)))
        }

        let count = 10
        let cycle = 0.8
        let colors: [Color] = [.white, Self.voiceDot, Color(red: 1, green: 0.97, blue: 0.75)]
        for index in 0..<count {
            let phase = now / cycle + Double(index) / Double(count)
            let progress = phase.truncatingRemainder(dividingBy: 1)
            let round = (phase - progress).rounded()
            let angle = (Double(index) * 2.399 + round * 1.7).truncatingRemainder(dividingBy: 2 * .pi)
            let distance = radius * (1.0 + 2.9 * progress)
            let starCenter = CGPoint(x: center.x + CGFloat(cos(angle)) * distance,
                                     y: center.y + CGFloat(sin(angle)) * distance)
            let size = radius * (index.isMultiple(of: 3) ? 1.15 : 0.8) * (1 - progress * 0.5)
            let spin = Angle.radians(progress * .pi / 2)
            var star = Path()
            star.move(to: CGPoint(x: 0, y: -size))
            star.addQuadCurve(to: CGPoint(x: size, y: 0), control: .zero)
            star.addQuadCurve(to: CGPoint(x: 0, y: size), control: .zero)
            star.addQuadCurve(to: CGPoint(x: -size, y: 0), control: .zero)
            star.addQuadCurve(to: CGPoint(x: 0, y: -size), control: .zero)
            let placed = star.applying(CGAffineTransform(rotationAngle: spin.radians))
                .applying(CGAffineTransform(translationX: starCenter.x, y: starCenter.y))
            let opacity = progress < 0.15 ? progress / 0.15 : 1 - (progress - 0.15) / 0.85
            context.fill(placed, with: .color(colors[index % colors.count].opacity(opacity)))
        }
    }

    /// The voice row and whether it is currently singing on pitch.
    private func voiceState(at now: TimeInterval) -> (row: Double, singing: Bool, onPitch: Bool) {
        let notes = Self.notes
        if let note = notes.first(where: { $0.start <= now && now < $0.end }) {
            let row = Double(note.row) + (note.isMissed ? 0.55 : 0)
            return (row, true, !note.isMissed)
        }
        let next = notes.first { $0.start > now } ?? notes[0]
        let previous = notes.last { $0.end <= now } ?? notes[notes.count - 1]
        let prevRow = Double(previous.row) + (previous.isMissed ? 0.55 : 0)
        let nextRow = Double(next.row) + (next.isMissed ? 0.55 : 0)
        let gapStart = previous.end, gapEnd = next.start > now ? next.start : next.start + Self.loop
        let progress = (now - gapStart) / max(gapEnd - gapStart, .ulpOfOne)
        let eased = progress * progress * (3 - 2 * progress)
        return (prevRow + (nextRow - prevRow) * min(max(eased, 0), 1), false, false)
    }
}
