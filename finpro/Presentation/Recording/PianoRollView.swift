//
//  PianoRollView.swift
//  finpro
//
//  Centre lane of the recording screen (PRD §5.5): target notes scroll past a playhead at 25%,
//  ~4 s visible, vertical range fitted to the current segment ± 3 semitones, and the user's
//  pitch trail in green (within tolerance) or red, and the lyric word under each note.
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
    static let rangePadding = 3
    /// C D E F G A B: the rows drawn and named, as in the design.
    static let naturalPitchClasses: Set<Int> = [0, 2, 4, 5, 7, 9, 11]

    let notes: [Note]
    let trail: [RecordingViewModel.TrailPoint]
    /// Notes of the current segment, used to fit the vertical range.
    let focusMIDI: [Int]
    let songTime: () -> TimeInterval?
    /// PRD §5.5: during pre-roll, notes before this time (previous material) are drawn greyed out.
    var dimmedBefore: TimeInterval?
    /// Stops redrawing (e.g. while a dialog is open) to leave CPU time for audio and video.
    var isPaused = false
    /// Lyric word sung on a note, drawn under it.
    var wordLabels: [UUID: String] = [:]
    /// Opacity of the dark panel behind the roll (a display setting).
    var backgroundOpacity = 0.6

    private let cornerRadius: CGFloat = 16
    private let labelWidth: CGFloat = 30

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: isPaused)) { _ in
            Canvas { context, size in
                draw(in: &context, size: size, now: songTime())
            }
        }
        .background(.black.opacity(backgroundOpacity), in: .rect(cornerRadius: cornerRadius))
        .overlay(alignment: .topLeading) {
            if trail.contains(where: { $0.midi != nil }) {
                Label {
                    Text("Your Voice")
                } icon: {
                    Circle().fill(Color.white).frame(width: 6, height: 6)
                }
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.leading, labelWidth)
                .padding(.top, 6)
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Pitch guide")
    }

    private var midiRange: ClosedRange<Int> {
        let low = (focusMIDI.min() ?? 60) - Self.rangePadding
        let high = (focusMIDI.max() ?? 60) + Self.rangePadding
        return low...max(high, low + 2 * Self.rangePadding)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, now: TimeInterval?) {
        let range = midiRange
        let rows = CGFloat(range.count)
        let rowHeight = size.height / rows
        let labelWidth = self.labelWidth
        let laneWidth = size.width - labelWidth
        let playheadX = labelWidth + laneWidth * Self.playheadPosition
        let current = now ?? 0
        func x(_ time: TimeInterval) -> CGFloat {
            playheadX + CGFloat((time - current) / Self.visibleDuration) * laneWidth
        }
        func y(_ midi: Double) -> CGFloat {
            size.height - (CGFloat(midi - Double(range.lowerBound)) + 0.5) * rowHeight
        }

        // Rows on the natural notes, named on the left edge as in the design.
        for midi in range where Self.naturalPitchClasses.contains((midi % 12 + 12) % 12) {
            let rowY = y(Double(midi))
            context.draw(Text(PitchMath.noteName(midi: midi)).font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.7)),
                         at: CGPoint(x: labelWidth / 2, y: rowY))
            var line = Path()
            line.move(to: CGPoint(x: labelWidth, y: rowY))
            line.addLine(to: CGPoint(x: size.width - 8, y: rowY))
            context.stroke(line, with: .color(.white.opacity(0.15)), lineWidth: 1)
        }

        guard now != nil else { return }
        context.clip(to: Path(CGRect(x: labelWidth, y: 0, width: laneWidth, height: size.height)))

        // Target notes.
        let windowStart = current - Self.visibleDuration * Self.playheadPosition
        let windowEnd = windowStart + Self.visibleDuration
        for note in notes where note.end > windowStart && note.start < windowEnd && range.contains(note.midi) {
            let height = max(4, min(10, rowHeight * 0.8))
            let rect = CGRect(x: x(note.start), y: y(Double(note.midi)) - height / 2,
                              width: max(height, x(note.end) - x(note.start) - 2), height: height)
            let isPrevious = dimmedBefore.map { note.end <= $0 + 1e-6 } ?? false
            let color: Color = note.isMissed ? .red : isPrevious ? .gray.opacity(0.45)
                : (note.start <= current && current < note.end ? .white : .white.opacity(0.85))
            context.fill(Path(roundedRect: rect, cornerRadius: height / 2), with: .color(color))
            if let word = wordLabels[note.id] {
                context.draw(Text(word).font(.system(size: 8, weight: .medium)).foregroundStyle(.white.opacity(0.85)),
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
            context.stroke(segment, with: .color(point.isHit ? .green : .red), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }

        // Playhead, with a dot where the voice is now.
        var playhead = Path()
        playhead.move(to: CGPoint(x: playheadX, y: 0))
        playhead.addLine(to: CGPoint(x: playheadX, y: size.height))
        context.stroke(playhead, with: .color(.white.opacity(0.9)), lineWidth: 2)
        if let last = trail.last, let midi = last.midi, current - last.songTime < maxJoin {
            let dot = CGRect(x: x(last.songTime) - 4, y: y(Double(midi)) - 4, width: 8, height: 8)
            context.fill(Path(ellipseIn: dot), with: .color(.white))
        }
    }
}

#Preview {
    let notes = DomainFixtures.segments.flatMap(\.targetNotes).map {
        PianoRollView.Note(id: $0.id, midi: $0.midiNote, start: $0.startTime, end: $0.endTime)
    }
    PianoRollView(notes: notes, trail: [], focusMIDI: notes.prefix(4).map(\.midi), songTime: { 1.5 })
        .frame(height: 180)
        .padding()
        .background(.gray)
}
