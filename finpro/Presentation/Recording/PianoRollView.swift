//
//  PianoRollView.swift
//  finpro
//
//  Pitch guide of the recording screen (PRD §5.5): target notes scroll past a playhead at 25%,
//  ~4 s visible, six lines centred on the notes on screen (gliding with the song), a dot where the user's
//  voice is now, grey notes whose passed part turns green (sung within tolerance) or red as it
//  is sung, and the lyric word under each note.
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
    }

    static let visibleDuration: TimeInterval = 4
    /// The voice dot while no voice is heard (resting on the next note): still visible, but
    /// clearly not "you are singing this".
    static let restingDotOpacity = 0.55
    static let playheadPosition = 0.25
    /// Distance between two lines (natural notes) in the design.
    static let rowPitch: CGFloat = 22
    /// Natural notes per octave and semitones per octave: a row is 12/7 semitones on average.
    private static let naturalsPerOctave: CGFloat = 7
    private static let semitonesPerOctave: CGFloat = 12
    /// Space above the first and below the last line.
    static let topInset: CGFloat = 13
    static let bottomInset: CGFloat = 14
    /// The playhead keeps its width at every size, as in the design.
    static let playheadWidth: CGFloat = 4
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

    /// A size that grows with the slider: `mid` is the design's default look at the middle of the
    /// slider, `high` the "Pitch Max" look at the right end, `low` the left end.
    static func scaled(_ scale: Double, low: CGFloat, mid: CGFloat, high: CGFloat) -> CGFloat {
        let clamped = min(max(scale, 0), 1)
        return clamped <= 0.5
            ? low + (mid - low) * CGFloat(clamped / 0.5)
            : mid + (high - mid) * CGFloat((clamped - 0.5) / 0.5)
    }

    /// Panel height for a number of lines, plus room for lyrics under them.
    static func height(rows: CGFloat, lyricsHeight: CGFloat = 0) -> CGFloat {
        topInset + rows * rowPitch + bottomInset + lyricsHeight
    }

    let notes: [Note]
    let trail: [RecordingViewModel.TrailPoint]
    /// Where the lime voice dot sits (smoothed, see VoiceDotFilter); nil hides it.
    var voiceDot: RecordingViewModel.VoiceDot?
    /// How the notes are coloured: while recording, or the results in the cover preview.
    var noteStyle: NoteStyle = .live
    /// Notes of the current segment, used to centre the vertical range.
    let focusMIDI: [Int]
    let songTime: () -> TimeInterval?
    /// PRD §5.5: notes before this time (material before the part being sung) are drawn greyed out.
    var dimmedBefore: TimeInterval?
    /// Stops redrawing (e.g. while a dialog is open) to leave CPU time for audio and video.
    var isPaused = false
    /// The lime dot of the live voice (off in the preview, which has no voice data).
    var showsVoiceDot = true
    /// Lyric word sung on a note, drawn under it.
    var wordLabels: [UUID: String] = [:]
    /// Height reserved at the bottom for content drawn over the roll (the lyrics, in Concept 2).
    var lyricsHeight: CGFloat = 0
    /// Size of the notes, lines and voice dot (a display setting, see `scaled`).
    var scale = RecordingDisplaySettings.defaultPitchGuideScale
    /// The user resized the panel: this many lines always fill its height (instead of as many as
    /// fit), and notes, dot and labels grow or shrink by `contentZoom` with it.
    var fixedRows: Double?
    var contentZoom: CGFloat = 1

    /// Extra lines the view may add when the notes on screen do not fit (at most 8 in all with
    /// the design's 6).
    static let maximumExtraLines: Double = 2
    /// Notes this close to the playhead decide the range when the whole screen does not fit.
    static let nearWindow: ClosedRange<TimeInterval> = -0.5...1.5
    /// Notes ahead used to place the lines while none is on screen.
    static let upcomingNoteCount = 4

    enum NoteStyle {
        /// Recording (user decision 2026-11-20): notes are never judged on screen. The part the
        /// playhead has passed turns grey, the rest is white, and the lime dot sparkles while the
        /// voice is on the note.
        case live
        /// Cover preview: each sung note green or red (missed), so the singer sees where it went
        /// wrong; notes of segments not in the cover stay white.
        case review(hit: Set<UUID>, missed: Set<UUID>)
    }
    @State private var viewport = PianoRollViewport()
    @State private var dotMotion = VoiceDotMotion()

    private let cornerRadius: CGFloat = 16
    private let labelWidth: CGFloat = 35
    private let trailInset: CGFloat = 10

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: isPaused)) { _ in
            Canvas { context, size in
                draw(in: &context, size: size, now: songTime())
            }
        }
        .background {
            // Sketch: material "Dark / Regular" (a background blur) with a light tint on top.
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
                    .environment(\.colorScheme, .dark)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Palette.panel)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Pitch guide")
    }

    // MARK: - Colors

    /// The frosted panel of the design: a blurred dark material under a light tint at 20%, plum lines, light
    /// notes (3rd Iteration), light labels, a dark playhead and a lime dot where the voice is.
    private enum Palette {
        static let panel = Color.secondaryButton.opacity(0.2)
        static let line = Color.tertiaryText.opacity(0.6)
        static let label = Color.secondaryButton
        /// A note not passed yet.
        static let note = Color.secondaryButton
        /// The part of a note the playhead has passed while recording.
        static let passedNote = Color.gray
        /// Notes of the segments before the one being sung.
        static let previousNote = Color.gray.opacity(0.6)
        static let playhead = Color.primary800
        static let dot = Color.secBrand
        static let word = Color.secondaryButton
    }

    private var noteHeight: CGFloat { Self.scaled(scale, low: 5, mid: 8, high: 16) * contentZoom }
    private var lineWidth: CGFloat { Self.scaled(scale, low: 1, mid: 2, high: 4) * min(contentZoom, 1.5) }
    private var dotSize: CGFloat { Self.scaled(scale, low: 8, mid: 12, high: 22) * contentZoom }

    // MARK: - Drawing

    /// Recording: greys the part of the note the playhead has passed.
    private func fillPassed(_ shape: Path, upTo current: TimeInterval, in context: inout GraphicsContext,
                            x: (TimeInterval) -> CGFloat) {
        let bounds = shape.boundingRect
        let passed = min(bounds.maxX, x(current))
        guard passed > bounds.minX else { return }
        var clipped = context
        clipped.clip(to: shape)
        clipped.fill(Path(CGRect(x: bounds.minX, y: bounds.minY, width: passed - bounds.minX, height: bounds.height)),
                     with: .color(Palette.passedNote))
    }

    /// The voice's recent pitch as a lime comet tail behind the dot: thick and bright at the dot,
    /// thinner and fading to the left. Breaks where the singer paused. Samples within the green
    /// tolerance of the note sung then sit on that note, like the dot.
    private func drawTrail(to dot: CGPoint?, current: TimeInterval, windowStart: TimeInterval, width: CGFloat,
                           in context: inout GraphicsContext, x: (TimeInterval) -> CGFloat, y: (Double) -> CGFloat) {
        let length = Self.visibleDuration * Self.playheadPosition
        let gap = 0.15
        var points: [(time: TimeInterval, point: CGPoint)?] = []
        var lastTime: TimeInterval?
        for sample in trail where sample.songTime >= windowStart && sample.songTime <= current {
            guard let midi = sample.midi else { points.append(nil); lastTime = nil; continue }
            if let lastTime, sample.songTime - lastTime > gap { points.append(nil) }
            var shown = Double(midi)
            if let note = notes.first(where: { $0.start <= sample.songTime && sample.songTime < $0.end }),
               abs(shown - Double(note.midi)) * 100 <= Double(NoteTally.toleranceCents) {
                shown = Double(note.midi)
            }
            points.append((sample.songTime, CGPoint(x: x(sample.songTime), y: y(shown))))
            lastTime = sample.songTime
        }
        // Joined to the dot while the voice is heard, so the tail ends where the dot is.
        if let dot, let lastTime, current - lastTime < gap * 3 { points.append((current, dot)) }

        var previous: (time: TimeInterval, point: CGPoint)?
        for entry in points {
            guard let entry else { previous = nil; continue }
            if let previous {
                let age = max(0, min(1, (current - entry.time) / length))
                var segment = Path()
                segment.move(to: previous.point)
                segment.addLine(to: entry.point)
                context.stroke(segment, with: .color(Palette.dot.opacity(0.9 * (1 - age))),
                               style: StrokeStyle(lineWidth: max(1, width * (1 - 0.7 * age)), lineCap: .round, lineJoin: .round))
            }
            previous = entry
        }
    }

    /// While the voice is on the note: a pulsing lime glow behind the dot, a ring spreading out
    /// and stars bursting away, a reward without judging the note itself.
    private func sparkle(around center: CGPoint, radius: CGFloat, at time: TimeInterval, in context: inout GraphicsContext) {
        // Glow, pulsing a few times a second.
        let pulse = 0.5 + 0.5 * sin(time * 2 * .pi * 2.5)
        var glow = context
        glow.addFilter(.blur(radius: radius * 1.2))
        let glowRadius = radius * (2.0 + 0.5 * pulse)
        glow.fill(Path(ellipseIn: CGRect(x: center.x - glowRadius, y: center.y - glowRadius,
                                         width: glowRadius * 2, height: glowRadius * 2)),
                  with: .color(Palette.dot.opacity(0.45 + 0.3 * pulse)))

        // Rings spreading out.
        for offset in [0.0, 0.5] {
            let progress = (time / 0.7 + offset).truncatingRemainder(dividingBy: 1)
            let ringRadius = radius * (1.1 + 1.9 * progress)
            context.stroke(Path(ellipseIn: CGRect(x: center.x - ringRadius, y: center.y - ringRadius,
                                                  width: ringRadius * 2, height: ringRadius * 2)),
                           with: .color(Palette.dot.opacity(0.8 * (1 - progress))), lineWidth: max(1, radius * 0.25 * (1 - progress)))
        }

        // Stars bursting away in new directions every round (golden angle spread).
        let count = 12
        let cycle = 0.8
        let colors: [Color] = [.white, Palette.dot, Color(red: 1, green: 0.97, blue: 0.75)]
        for index in 0..<count {
            let phase = time / cycle + Double(index) / Double(count)
            let progress = phase.truncatingRemainder(dividingBy: 1)
            let round = (phase - progress).rounded()
            let angle = (Double(index) * 2.399 + round * 1.7).truncatingRemainder(dividingBy: 2 * .pi)
            let distance = radius * (1.0 + 3.2 * progress)
            let point = CGPoint(x: center.x + CGFloat(cos(angle)) * distance, y: center.y + CGFloat(sin(angle)) * distance)
            let size = radius * (index.isMultiple(of: 3) ? 1.3 : 0.9) * (1 - progress * 0.5)
            let spin = Angle.radians(progress * .pi / 2)
            var star = Path()
            star.move(to: CGPoint(x: 0, y: -size))
            star.addQuadCurve(to: CGPoint(x: size, y: 0), control: .zero)
            star.addQuadCurve(to: CGPoint(x: 0, y: size), control: .zero)
            star.addQuadCurve(to: CGPoint(x: -size, y: 0), control: .zero)
            star.addQuadCurve(to: CGPoint(x: 0, y: -size), control: .zero)
            let placed = star.applying(CGAffineTransform(rotationAngle: spin.radians).translatedBy(x: 0, y: 0))
                .applying(CGAffineTransform(translationX: point.x, y: point.y))
            let opacity = progress < 0.15 ? progress / 0.15 : 1 - (progress - 0.15) / 0.85
            context.fill(placed, with: .color(colors[index % colors.count].opacity(opacity)))
        }
    }

    /// Centre and number of lines that show the notes on screen (or the segment's notes before
    /// any are on screen).
    private func targetLines(at current: TimeInterval, fitting rows: Double) -> (center: Double, span: Double) {
        let windowStart = current - Self.visibleDuration * Self.playheadPosition
        let windowEnd = windowStart + Self.visibleDuration
        func lines(_ midi: [Int]) -> (low: Double, high: Double)? {
            let positions = midi.map { Self.linePosition(of: Double($0)) }
            guard let low = positions.min(), let high = positions.max() else { return nil }
            return (low, high)
        }
        let onScreen = notes.filter { $0.end > windowStart && $0.start < windowEnd }.map(\.midi)
        let near = notes.filter { $0.end > current + Self.nearWindow.lowerBound && $0.start < current + Self.nearWindow.upperBound }
            .map(\.midi)
        let maximum = rows + Self.maximumExtraLines
        // Between phrases, the next notes to sing.
        let upcoming = notes.filter { $0.start >= windowEnd }.sorted { $0.start < $1.start }
            .prefix(Self.upcomingNoteCount).map(\.midi)
        let fallback = Self.linePosition(of: 60)
        var range = lines(onScreen) ?? lines(Array(upcoming)) ?? lines(focusMIDI) ?? (fallback, fallback)
        if range.high - range.low + 2 > maximum, let nearRange = lines(near) { range = nearRange }
        let span = min(maximum, max(rows, range.high - range.low + 2))
        return ((range.low + range.high) / 2, span)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, now: TimeInterval?) {
        let rowsTop = Self.topInset
        let rowsHeight = max(Self.rowPitch, size.height - Self.topInset - Self.bottomInset - lyricsHeight)

        let laneWidth = size.width - labelWidth - trailInset
        let playheadX = labelWidth + laneWidth * Self.playheadPosition
        let current = now ?? 0

        // The lines in view: as many as fit (6 in the design), centred on the notes on screen and
        // gliding as the song moves, so a wide segment or a stray note never squeezes the rows.
        let target = targetLines(at: current, fitting: fixedRows ?? rowsHeight / Self.rowPitch)
        // Lines sit in the middle of their rows (half a row free above the top line and below
        // the bottom one): with the lowest edge on a whole line, a 7th and 8th line peeked in
        // half-cut at the top and bottom edges.
        let alignedCenter = (target.center - target.span / 2 - 0.5).rounded() + target.span / 2 + 0.5
        let (center, span) = viewport.update(center: alignedCenter, span: target.span)
        let pitch = rowsHeight / span
        let lowLine = center - span / 2
        func x(_ time: TimeInterval) -> CGFloat {
            playheadX + CGFloat((time - current) / Self.visibleDuration) * laneWidth
        }
        func y(_ midi: Double) -> CGFloat {
            rowsTop + rowsHeight - CGFloat(Self.linePosition(of: midi) - lowLine) * pitch
        }

        // A line on every natural note, named on the left edge as in the design. Lines scroll in
        // and out at the panel's edges.
        var lineContext = context
        lineContext.clip(to: Path(CGRect(x: 0, y: rowsTop, width: size.width, height: rowsHeight)))
        for line in Int(lowLine.rounded(.down))...Int((lowLine + span).rounded(.up)) {
            let midi = Self.midi(onLine: line)
            let rowY = y(Double(midi))
            lineContext.draw(Text(PitchMath.noteName(midi: midi)).font(.system(size: 11 * min(contentZoom, 1.5), weight: .medium)).foregroundStyle(Palette.label),
                         at: CGPoint(x: labelWidth / 2 - 2, y: rowY))
            var path = Path()
            path.move(to: CGPoint(x: labelWidth, y: rowY))
            path.addLine(to: CGPoint(x: size.width - trailInset, y: rowY))
            lineContext.stroke(path, with: .color(Palette.line), lineWidth: lineWidth)
        }

        guard now != nil else { return }
        // Notes above or below the lines in view stay hidden until the lines glide to them.
        let noteMargin = noteHeight / 2
        context.clip(to: Path(CGRect(x: labelWidth, y: rowsTop - noteMargin, width: laneWidth + trailInset,
                                     height: rowsHeight + noteMargin * 2)))

        // Target notes.
        let windowStart = current - Self.visibleDuration * Self.playheadPosition
        let windowEnd = windowStart + Self.visibleDuration
        var drawnLabels: [CGRect] = []
        let labelSpacing: CGFloat = 3
        for note in notes where note.end > windowStart && note.start < windowEnd {
            let height = noteHeight
            let rect = CGRect(x: x(note.start), y: y(Double(note.midi)) - height / 2,
                              width: max(height, x(note.end) - x(note.start) - 2), height: height)
            let shape = Path(roundedRect: rect, cornerRadius: height / 2)
            switch noteStyle {
            case .live:
                let isPrevious = dimmedBefore.map { note.end <= $0 + 1e-6 } ?? false
                context.fill(shape, with: .color(isPrevious ? Palette.previousNote : Palette.note))
                if !isPrevious { fillPassed(shape, upTo: current, in: &context, x: x) }
            case .review(let hit, let missed):
                let color = missed.contains(note.id) ? Color.noteMiss : hit.contains(note.id) ? Color.pitchHit : Palette.note
                context.fill(shape, with: .color(color))
            }
            if let word = wordLabels[note.id] {
                // A word that would run into an earlier one (short notes close together) is left
                // out; the lyric line under the guide still shows it.
                let label = context.resolve(Text(word).font(.system(size: 8 * min(contentZoom, 1.5), weight: .medium))
                    .foregroundStyle(Palette.word))
                let frame = CGRect(origin: CGPoint(x: rect.minX + 2, y: rect.maxY + 2),
                                   size: label.measure(in: CGSize(width: CGFloat.infinity, height: .infinity)))
                if !drawnLabels.contains(where: { $0.insetBy(dx: -labelSpacing, dy: 0).intersects(frame) }) {
                    context.draw(label, in: frame)
                    drawnLabels.append(frame)
                }
            }
        }

        // The voice is a dot at the playhead with a fading trail behind it (trail back on
        // 2026-11-20, user request). The pitch pipeline lags the song clock by ~0.1 s, so a voice
        // heard within this long still counts as singing now.
        let dotHold = 0.3

        // Playhead, with a dot where the voice is now.
        var playhead = Path()
        playhead.move(to: CGPoint(x: playheadX, y: rowsTop))
        playhead.addLine(to: CGPoint(x: playheadX, y: rowsTop + rowsHeight))
        context.stroke(playhead, with: .color(Palette.playhead), lineWidth: Self.playheadWidth)
        // The dot never disappears (user decision 2026-11-16). It is drawn like a magnet:
        // - silent: it rests on the note being sung now, or else the next one, a little faded;
        // - singing within the green tolerance of that note: it sits exactly on the note;
        // - singing further off: it shows the voice's real pitch.
        // Every move glides (VoiceDotMotion) instead of jumping.
        let magnet = notes.first { $0.start <= current && current < $0.end }
            ?? notes.filter { $0.start > current }.min { $0.start < $1.start }
        guard showsVoiceDot else { return }
        let singing = voiceDot.map { current - $0.songTime < dotHold } ?? false
        var dotTarget: Double?
        var onPitch = false
        if singing, let voiceDot {
            let sung = Double(voiceDot.midi)
            if let magnet, current >= magnet.start, abs(sung - Double(magnet.midi)) * 100 <= Double(NoteTally.toleranceCents) {
                dotTarget = Double(magnet.midi)
                onPitch = true
            } else {
                dotTarget = sung
            }
        } else if let magnet {
            dotTarget = Double(magnet.midi)
        } else if let voiceDot {
            dotTarget = Double(voiceDot.midi)
        }
        if let dotTarget {
            let midi = dotMotion.update(target: dotTarget)
            let radius = dotSize / 2
            // Pinned to the top or bottom line when the voice is outside the lines in view.
            let dotY = min(max(y(midi), rowsTop + radius), rowsTop + rowsHeight - radius)
            // On the playhead: the dot is "now"; drawing it at the sample's time made it shake sideways.
            let dot = CGRect(x: playheadX - radius, y: dotY - radius, width: dotSize, height: dotSize)
            drawTrail(to: singing ? CGPoint(x: playheadX, y: dotY) : nil, current: current, windowStart: windowStart,
                      width: dotSize * 0.5, in: &context, x: x, y: { min(max(y($0), rowsTop), rowsTop + rowsHeight) })
            if onPitch { sparkle(around: CGPoint(x: playheadX, y: dotY), radius: radius, at: current, in: &context) }
            context.fill(Path(ellipseIn: dot), with: .color(Palette.dot.opacity(singing ? 1 : Self.restingDotOpacity)))
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
