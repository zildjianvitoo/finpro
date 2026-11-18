//
//  PitchGuideIllustrationCard.swift
//  finpro
//
//  The pitch guide card of onboarding page 1, drawn natively so it plays like the real guide:
//  word notes scroll past the playhead, the voice dot follows the melody, and the part of a note
//  the dot has passed turns green (one short slip shows red). Laid out in the illustration's
//  pixels (docs/illustrations/ob1-full.png), scaled by `unit`.
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
        /// The first seconds of the note sung off pitch (shown red, the dot below the note).
        var slip: TimeInterval = 0
    }

    private static let rowNames = ["C4", "B3", "A3", "G3", "F3", "E3", "D3"]
    private static let lines = ["A whole new world", "A hundred thousand things to see"]
    /// One loop of the melody; the second line starts at `secondLineStart`.
    private static let notes: [Note] = [
        Note(word: "A", row: 4, start: 0.0, end: 0.6),
        Note(word: "whole", row: 3, start: 0.8, end: 1.7, slip: 0.3),
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
    /// The resting frame: the dot just past the slip of "whole", as in the design.
    private static let restingTime: TimeInterval = 1.2

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
    private static let dotSize: CGFloat = 58
    private static let lyricsY: CGFloat = 556
    private static let lyricsStep: CGFloat = 50

    // Colours of the illustration's frosted card.
    private static let cardCentre = Color(red: 146 / 255, green: 89 / 255, blue: 130 / 255)
    private static let cardEdge = Color(red: 206 / 255, green: 181 / 255, blue: 199 / 255)
    private static let rowLine = Color(white: 201 / 255)
    private static let playhead = Color(red: 102 / 255, green: 50 / 255, blue: 80 / 255)

    var body: some View {
        Canvas { context, _ in draw(in: &context) }
            .frame(width: Self.size.width * unit, height: Self.size.height * unit)
            .background(
                RadialGradient(colors: [Self.cardCentre, Self.cardEdge], center: .center,
                               startRadius: 0, endRadius: Self.size.width * 0.62 * unit)
                    .opacity(0.94)
            )
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius * unit, style: .continuous))
    }

    private func draw(in context: inout GraphicsContext) {
        let now = (time == 0 ? Self.restingTime : time).truncatingRemainder(dividingBy: Self.loop)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * unit, y: y * unit) }
        func rowY(_ row: Double) -> CGFloat { Self.firstRowY + CGFloat(row) * Self.rowStep }

        // Rows with their note names.
        for (index, name) in Self.rowNames.enumerated() {
            let y = rowY(Double(index))
            context.draw(Text(name).font(.system(size: 24 * unit, weight: .medium)).foregroundStyle(.white.opacity(0.8)),
                         at: point(Self.labelX, y))
            var line = Path()
            line.move(to: point(Self.laneStart, y))
            line.addLine(to: point(Self.laneEnd, y))
            context.stroke(line, with: .color(Self.rowLine), lineWidth: 12 * unit)
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
                let rect = CGRect(x: x0 * unit, y: (y - Self.noteHeight / 2) * unit,
                                  width: max(Self.noteHeight, x1 - x0) * unit, height: Self.noteHeight * unit)
                let shape = Path(roundedRect: rect, cornerRadius: rect.height / 2)
                lane.fill(shape, with: .color(.white))
                // The sung part: red over the slip, green after it.
                var sung = lane
                sung.clip(to: shape)
                let slipEnd = Self.playheadX + CGFloat(start + note.slip - now) * Self.pointsPerSecond
                let passed = min(x1, Self.playheadX)
                if passed > x0 {
                    let redEnd = min(passed, slipEnd)
                    if redEnd > x0 {
                        sung.fill(Path(CGRect(x: x0 * unit, y: rect.minY, width: (redEnd - x0) * unit, height: rect.height)),
                                  with: .color(.noteMiss))
                    }
                    let greenStart = max(x0, slipEnd)
                    if passed > greenStart {
                        sung.fill(Path(CGRect(x: greenStart * unit, y: rect.minY, width: (passed - greenStart) * unit, height: rect.height)),
                                  with: .color(.pitchHit))
                    }
                }
                lane.draw(Text(note.word).font(.system(size: 24 * unit, weight: .medium)).foregroundStyle(.white),
                          at: point(x0 + 6, y + Self.noteHeight / 2 + 4), anchor: .topLeading)
            }
        }

        // Playhead, and the voice dot at the pitch being sung (gliding between notes).
        var playhead = Path()
        playhead.move(to: point(Self.playheadX, Self.playheadTop))
        playhead.addLine(to: point(Self.playheadX, Self.playheadBottom))
        context.stroke(playhead, with: .color(Self.playhead), lineWidth: 10 * unit)
        let dotRow = voiceRow(at: now)
        let dot = CGRect(x: (Self.playheadX - Self.dotSize / 2) * unit, y: (rowY(dotRow) - Self.dotSize / 2) * unit,
                         width: Self.dotSize * unit, height: Self.dotSize * unit)
        context.fill(Path(ellipseIn: dot), with: .color(.primaryBrand))

        // Lyrics: the line being sung, then the next one.
        let current = now < Self.secondLineStart ? 0 : 1
        for (offset, index) in [current, 1 - current].enumerated() {
            context.draw(Text(Self.lines[index]).font(.system(size: 34 * unit, weight: offset == 0 ? .semibold : .regular))
                            .foregroundStyle(.white.opacity(offset == 0 ? 1 : 0.75)),
                         at: point(Self.size.width / 2, Self.lyricsY + CGFloat(offset) * Self.lyricsStep))
        }
    }

    /// The row the voice is on: the note's row (a little low during a slip), gliding between notes.
    private func voiceRow(at now: TimeInterval) -> Double {
        let notes = Self.notes
        if let note = notes.first(where: { $0.start <= now && now < $0.end }) {
            return Double(note.row) + (now < note.start + note.slip ? 0.5 : 0)
        }
        let next = notes.first { $0.start > now } ?? notes[0]
        let previous = notes.last { $0.end <= now } ?? notes[notes.count - 1]
        let gapStart = previous.end, gapEnd = next.start > now ? next.start : next.start + Self.loop
        let progress = (now - gapStart) / max(gapEnd - gapStart, .ulpOfOne)
        let eased = progress * progress * (3 - 2 * progress)
        return Double(previous.row) + (Double(next.row) - Double(previous.row)) * min(max(eased, 0), 1)
    }
}
