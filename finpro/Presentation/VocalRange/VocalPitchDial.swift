//
//  VocalPitchDial.swift
//  finpro
//
//  Live pitch on the lowest/highest note steps (Sketch "3rd Iteration" 2.4 / 2.5): a curved
//  tuner. The marker at the top stays put; the semitone scale turns under it so the note being
//  sung sits at the marker, with its name and frequency above.
//

import SwiftUI

struct VocalPitchDial: View {
    let midi: Float?
    let referenceMIDI: Float
    /// The curved band behind the ticks (light lime on the lowest step, lime on the highest).
    let bandColor: Color
    @State private var lastHeardMIDI: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var position: LivePitchPositionUseCase.Position? { LivePitchPositionUseCase().execute(midi: midi) }
    private var reference: Double {
        referenceMIDI.isFinite ? min(127, max(0, Double(referenceMIDI))) : 57
    }
    /// Snapped to the nearest semitone, so the scale glides from note to note instead of shaking.
    private var shownMIDI: Double { position?.noteMIDI ?? lastHeardMIDI ?? reference }

    var body: some View {
        PitchArcScale(center: shownMIDI, hasVoice: position != nil || lastHeardMIDI != nil, bandColor: bandColor)
            .frame(width: PitchArcScale.size.width, height: PitchArcScale.size.height)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: shownMIDI)
            .onChange(of: midi, initial: true) { _, _ in
                if let position { lastHeardMIDI = position.noteMIDI }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Detected pitch")
            .accessibilityValue(spokenDescription)
    }

    private var spokenDescription: String {
        guard let position else { return "No voice detected" }
        return "\(PitchMath.noteName(midi: position.nearestNote)), \(Int(PitchMath.frequency(fromMIDI: position.midi))) hertz"
    }
}

/// The drawing, animatable on `center` so the scale turns smoothly. Sizes are the design's (295 × 235 pt).
private struct PitchArcScale: View, Animatable {
    var center: Double
    let hasVoice: Bool
    let bandColor: Color

    static let size = CGSize(width: 295, height: 235)
    /// Ellipse the tick tops sit on.
    private static let tickCenter = CGPoint(x: 147.5, y: 170)
    private static let tickRadii = CGSize(width: 150, height: 99)
    /// Angle between two semitones along the ellipse.
    private static let semitoneAngle = 21.0
    private static let ticksPerSemitone = 5
    private static let maxAngle = 72.0

    var animatableData: Double {
        get { center }
        set { center = newValue }
    }

    var body: some View {
        Canvas { context, _ in
            context.fill(band, with: .color(bandColor))
            let first = Int(floor(center - Self.maxAngle / Self.semitoneAngle)) * Self.ticksPerSemitone
            let last = Int(ceil(center + Self.maxAngle / Self.semitoneAngle)) * Self.ticksPerSemitone
            for tick in first...last {
                let note = Double(tick) / Double(Self.ticksPerSemitone)
                let angle = (note - center) * Self.semitoneAngle
                guard abs(angle) <= Self.maxAngle else { continue }
                let major = tick.isMultiple(of: Self.ticksPerSemitone)
                // The marker covers the tick under it.
                if major, abs(angle) < Self.semitoneAngle / 2 { continue }
                drawTick(in: context, angle: angle, width: major ? 6 : 3, length: major ? 34 : 24,
                         color: major ? .primary300 : .tertiaryText)
                if major, abs(angle) <= Self.semitoneAngle * 2.2 { drawSideLabel(in: context, note: Int(note.rounded()), angle: angle) }
            }
            drawTick(in: context, angle: 0, width: 6, length: 36, color: .primaryBrand)
            drawCenterLabel(in: context)
        }
    }

    /// Point on the tick ellipse and the outward direction there (radians from straight up).
    private func point(at degrees: Double, outset: CGFloat = 0) -> (CGPoint, Double) {
        let theta = degrees * .pi / 180
        let rx = Self.tickRadii.width, ry = Self.tickRadii.height
        let normal = atan2(sin(theta) / rx, cos(theta) / ry)
        let base = CGPoint(x: Self.tickCenter.x + rx * sin(theta), y: Self.tickCenter.y - ry * cos(theta))
        return (CGPoint(x: base.x + outset * sin(normal), y: base.y - outset * cos(normal)), normal)
    }

    private func drawTick(in context: GraphicsContext, angle: Double, width: CGFloat, length: CGFloat, color: Color) {
        let (top, normal) = point(at: angle)
        var local = context
        local.translateBy(x: top.x, y: top.y)
        local.rotate(by: .radians(normal))
        local.fill(Path(roundedRect: CGRect(x: -width / 2, y: 0, width: width, height: length), cornerRadius: width / 2),
                   with: .color(color))
    }

    private func drawSideLabel(in context: GraphicsContext, note: Int, angle: Double) {
        let (at, normal) = point(at: angle, outset: 20)
        var local = context
        local.translateBy(x: at.x, y: at.y)
        local.rotate(by: .radians(normal))
        local.opacity = max(0, 1 - abs(angle) / Self.maxAngle * 0.4)
        local.draw(Text(PitchMath.noteName(midi: note)).font(.appTitle2.weight(.bold)).foregroundStyle(Color.primary300),
                   at: .zero, anchor: .bottom)
    }

    private func drawCenterLabel(in context: GraphicsContext) {
        let note = Int(center.rounded())
        let (top, _) = point(at: 0)
        let name = hasVoice ? PitchMath.noteName(midi: note) : "–"
        let hertz = hasVoice ? "(\(Int(PitchMath.frequency(fromMIDI: Double(note)).rounded())) Hz)" : " "
        context.draw(Text(hertz).font(.appSubheadline).foregroundStyle(Color.primary300),
                     at: CGPoint(x: top.x, y: top.y - 19), anchor: .bottom)
        context.draw(Text(name).font(.appTitle2.weight(.bold)).foregroundStyle(Color.primaryBrand),
                     at: CGPoint(x: top.x, y: top.y - 38), anchor: .bottom)
    }

    /// Upper part of an elliptical ring; its ends stop where the design's do.
    private var band: Path {
        let outer = Path(ellipseIn: CGRect(x: 0, y: 67, width: 295, height: 167))
        let inner = Path(ellipseIn: CGRect(x: 24, y: 113, width: 249, height: 107))
        let cut = Path(CGRect(x: 36, y: 171, width: 216, height: 67))
        return outer.subtracting(inner).subtracting(cut)
    }
}

#Preview {
    VStack(spacing: 40) {
        VocalPitchDial(midi: 40, referenceMIDI: 50, bandColor: .secondary200)
        VocalPitchDial(midi: nil, referenceMIDI: 57, bandColor: .secBrand)
    }
}
