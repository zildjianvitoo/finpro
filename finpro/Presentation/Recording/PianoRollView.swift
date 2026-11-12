//
//  PianoRollView.swift
//  finpro
//
//  Pitch guide of the recording screen (PRD §5.5): target notes scroll past a playhead at 25%,
//  ~4 s visible, the vertical range centred on the current segment, and the user's pitch trail
//  in green (within tolerance) or red, with the lyric word under each note.
//  UI only — never part of the recording.
//

import SwiftUI

struct PianoRollView: View {
    struct Note: Identifiable {
        let id: UUID
        /// Transposed MIDI note, as the user should sing it.
        let midi: Int
        let start: TimeInterval
        let end: TimeInterval
        var isMissed = false
    }

    static let visibleDuration: TimeInterval = 4
    static let playheadPosition = 0.25
    /// Distance between two lines (natural notes) in the design.
    static let rowPitch: CGFloat = 22
    /// Natural notes per octave and semitones per octave: a row is 12/7 semitones on average.
    private static let naturalsPerOctave: CGFloat = 7
    private static let semitonesPerOctave: CGFloat = 12
    /// Space above the first and below the last line.
    static let topInset: CGFloat = 13
    static let bottomInset: CGFloat = 14
    static let noteHeight: CGFloat = 16
    /// C D E F G A B: the rows drawn and named, as in the design.
    static let naturalPitchClasses: [Int] = [0, 2, 4, 5, 7, 9, 11]

    /// Position of a note on the lines of the natural notes (7 per octave): the lines are evenly
    /// spaced, a sharp or flat sits halfway between its neighbours, and a pitch between two
    /// semitones is interpolated.
    static func linePosition(of midi: Double) -> Double {
        let lower = midi.rounded(.down)
        let fraction = midi - lower
        let a = linePosition(of: Int(lower))
        let b = linePosition(of: Int(lower) + 1)
        return a + (b - a) * fraction
    }

    private static func linePosition(of midi: Int) -> Double {
        let octave = Int((Double(midi) / 12).rounded(.down))
        let pitchClass = midi - octave * 12
        if let index = naturalPitchClasses.firstIndex(of: pitchClass) {
            return Double(octave * 7 + index)
        }
        let below = naturalPitchClasses.lastIndex { $0 < pitchClass } ?? 0
        return Double(octave * 7 + below) + 0.5
    }

    /// The MIDI note on a line of the natural notes.
    private static func midi(onLine line: Int) -> Int {
        let octave = Int((Double(line) / 7).rounded(.down))
        return octave * 12 + naturalPitchClasses[line - octave * 7]
    }

    /// Panel height for a number of lines, plus room for lyrics under them.
    static func height(rows: CGFloat, lyricsHeight: CGFloat = 0) -> CGFloat {
        topInset + rows * rowPitch + bottomInset + lyricsHeight
    }

    let notes: [Note]
    let trail: [RecordingViewModel.TrailPoint]
    /// Notes of the current segment, used to centre the vertical range.
    let focusMIDI: [Int]
    let songTime: () -> TimeInterval?
    /// PRD §5.5: during pre-roll, notes before this time (previous material) are drawn greyed out.
    var dimmedBefore: TimeInterval?
    /// Stops redrawing (e.g. while a dialog is open) to leave CPU time for audio and video.
    var isPaused = false
    /// Lyric word sung on a note, drawn under it.
    var wordLabels: [UUID: String] = [:]
    /// Height reserved at the bottom for content drawn over the roll (the lyrics, in Concept 2).
    var lyricsHeight: CGFloat = 0
    /// Opacity of the panel behind the roll (a display setting).
    var backgroundOpacity = RecordingDisplaySettings.defaultPitchGuideOpacity

    private let cornerRadius: CGFloat = 16
    private let labelWidth: CGFloat = 35
    private let trailInset: CGFloat = 10
    private let lineWidth: CGFloat = 3

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: isPaused)) { _ in
            Canvas { context, size in
                draw(in: &context, size: size, now: songTime())
            }
        }
        .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(Color.secondaryButton.opacity(backgroundOpacity)))
        .accessibilityElement()
        .accessibilityLabel("Pitch guide")
    }

    // MARK: - Colors

    /// The plum-tinted light panel of the design, for both lyric placements.
    private enum Palette {
        static let line = Color.tertiaryText.opacity(0.8)
        static let label = Color.primaryBrand
        static let note = Color.secondaryText
        static let playhead = Color.primary800
        static let dot = Color.secBrand
        static let word = Color.primaryBrand
        static let dotSize: CGFloat = 22
    }

    // MARK: - Drawing

    private func draw(in context: inout GraphicsContext, size: CGSize, now: TimeInterval?) {
        let rowsTop = Self.topInset
        let rowsHeight = max(Self.rowPitch, size.height - Self.topInset - Self.bottomInset - lyricsHeight)

        // Lines that fit the area, centred on the focus notes; the area grows past its size when
        // the segment is wider, so every note of the segment stays in view.
        let focusLines = focusMIDI.map { Self.linePosition(of: Double($0)) }
        let lowFocus = focusLines.min() ?? Self.linePosition(of: 60)
        let highFocus = focusLines.max() ?? Self.linePosition(of: 60)
        let span = max(rowsHeight / Self.rowPitch, highFocus - lowFocus + 2)
        let pitch = rowsHeight / span
        let lowLine = ((lowFocus + highFocus) / 2 - span / 2).rounded() - 0.5

        let laneWidth = size.width - labelWidth - trailInset
        let playheadX = labelWidth + laneWidth * Self.playheadPosition
        let current = now ?? 0
        func x(_ time: TimeInterval) -> CGFloat {
            playheadX + CGFloat((time - current) / Self.visibleDuration) * laneWidth
        }
        func y(_ midi: Double) -> CGFloat {
            rowsTop + rowsHeight - CGFloat(Self.linePosition(of: midi) - lowLine) * pitch
        }

        // A line on every natural note, named on the left edge as in the design.
        for line in Int((lowLine + 0.5).rounded(.up))...Int((lowLine + span - 0.5).rounded(.down)) {
            let midi = Self.midi(onLine: line)
            let rowY = y(Double(midi))
            context.draw(Text(PitchMath.noteName(midi: midi)).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.label),
                         at: CGPoint(x: labelWidth / 2 - 2, y: rowY))
            var path = Path()
            path.move(to: CGPoint(x: labelWidth, y: rowY))
            path.addLine(to: CGPoint(x: size.width - trailInset, y: rowY))
            context.stroke(path, with: .color(Palette.line), lineWidth: lineWidth)
        }

        guard now != nil else { return }
        context.clip(to: Path(CGRect(x: labelWidth, y: 0, width: laneWidth + trailInset, height: size.height)))

        // Target notes.
        let windowStart = current - Self.visibleDuration * Self.playheadPosition
        let windowEnd = windowStart + Self.visibleDuration
        for note in notes where note.end > windowStart && note.start < windowEnd {
            let height = Self.noteHeight
            let rect = CGRect(x: x(note.start), y: y(Double(note.midi)) - height / 2,
                              width: max(height, x(note.end) - x(note.start) - 2), height: height)
            let isPrevious = dimmedBefore.map { note.end <= $0 + 1e-6 } ?? false
            let isHit = !note.isMissed && trail.contains { $0.isHit && $0.songTime >= note.start && $0.songTime < note.end }
            let color: Color = note.isMissed ? .noteMiss : isPrevious ? .gray.opacity(0.45)
                : isHit ? .pitchHit
                : Palette.note.opacity(note.start <= current && current < note.end ? 1 : 0.85)
            context.fill(Path(roundedRect: rect, cornerRadius: height / 2), with: .color(color))
            if let word = wordLabels[note.id] {
                context.draw(Text(word).font(.system(size: 8, weight: .medium)).foregroundStyle(Palette.word),
                             at: CGPoint(x: rect.minX + 2, y: rect.maxY + 2), anchor: .topLeading)
            }
        }

        // Pitch trail: consecutive voiced points are joined; unvoiced breaks the line.
        let maxJoin = 0.12
        for (previous, point) in zip(trail, trail.dropFirst()) {
            guard let a = previous.midi, let b = point.midi, point.songTime - previous.songTime <= maxJoin else { continue }
            var segment = Path()
            segment.move(to: CGPoint(x: x(previous.songTime), y: y(Double(a))))
            segment.addLine(to: CGPoint(x: x(point.songTime), y: y(Double(b))))
            context.stroke(segment, with: .color(point.isHit ? .pitchHit : .noteMiss), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }

        // Playhead, with a dot where the voice is now.
        var playhead = Path()
        playhead.move(to: CGPoint(x: playheadX, y: rowsTop))
        playhead.addLine(to: CGPoint(x: playheadX, y: rowsTop + rowsHeight))
        context.stroke(playhead, with: .color(Palette.playhead), lineWidth: 2)
        if let last = trail.last, let midi = last.midi, current - last.songTime < maxJoin {
            let radius = Palette.dotSize / 2
            let dot = CGRect(x: x(last.songTime) - radius, y: y(Double(midi)) - radius, width: Palette.dotSize, height: Palette.dotSize)
            context.fill(Path(ellipseIn: dot), with: .color(Palette.dot))
        }
    }
}

#Preview {
    let notes = DomainFixtures.segments.flatMap(\.targetNotes).map {
        PianoRollView.Note(id: $0.id, midi: $0.midiNote, start: $0.startTime, end: $0.endTime)
    }
    VStack {
        PianoRollView(notes: notes, trail: [], focusMIDI: notes.prefix(4).map(\.midi), songTime: { 1.5 })
            .frame(height: PianoRollView.height(rows: 6))
        PianoRollView(notes: notes, trail: [], focusMIDI: notes.prefix(4).map(\.midi), songTime: { 1.5 },
                      lyricsHeight: 44)
            .frame(height: PianoRollView.height(rows: 6, lyricsHeight: 44))
    }
    .padding()
    .background(.gray)
}
