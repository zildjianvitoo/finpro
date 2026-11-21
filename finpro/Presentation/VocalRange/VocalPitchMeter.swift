//
//  VocalPitchMeter.swift
//  finpro
//
//  Live pitch on the lowest/highest note steps (design 2.4 / 2.5, revision 2026-11-21): a
//  vertical bar with a lime dot. The dot follows the voice up and down like a tuner needle
//  (springy, between the rows too); the note names beside the bar only slide when the dot nears
//  an end of the bar. While a note is held the dot grows and glows; when it is captured it pops.
//  The bar glows pink toward the end the singer is looking for (the bottom for the lowest note,
//  the top for the highest).
//

import SwiftUI

struct VocalPitchMeter: View {
    enum Direction { case lowest, highest }

    let midi: Float?
    let referenceMIDI: Float
    let direction: Direction
    /// 0…1 while a steady note is held (1 s to capture).
    var holdProgress: Double = 0
    var isCaptured = false

    /// The semitone on the dot's home row; moves by whole notes when the dot nears an end.
    @State private var windowCenter: Double?
    @State private var lastHeardMIDI: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var position: LivePitchPositionUseCase.Position? { LivePitchPositionUseCase().execute(midi: midi) }
    private var reference: Double {
        referenceMIDI.isFinite ? min(127, max(0, Double(referenceMIDI))) : 57
    }
    private var window: Double { windowCenter ?? reference }

    var body: some View {
        let geometry = PitchMeterGeometry(direction: direction)
        // Silent: the dot drifts back to its home row and fades.
        let dotMIDI = position?.midi ?? window
        ZStack(alignment: .topLeading) {
            PitchMeterBar(direction: direction, geometry: geometry)
            PitchMeterLabels(center: window, currentNote: position?.nearestNote, geometry: geometry)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: window)
            if lastHeardMIDI != nil {
                PitchMeterDot(holdProgress: position == nil ? 0 : holdProgress, isCaptured: isCaptured,
                              isHearing: position != nil, reduceMotion: reduceMotion)
                    .position(x: geometry.barMidX, y: geometry.y(of: dotMIDI, window: window))
                    .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.72), value: dotMIDI)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: window)
            }
        }
        .frame(width: PitchMeterGeometry.size.width, height: PitchMeterGeometry.size.height, alignment: .topLeading)
        .onChange(of: midi, initial: true) { _, _ in follow() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Detected pitch")
        .accessibilityValue(spokenDescription)
    }

    /// Keeps the dot on the bar: once it nears an end, the names slide so the note sung sits on
    /// the home row again.
    private func follow() {
        guard let position else { return }
        lastHeardMIDI = position.midi
        let geometry = PitchMeterGeometry(direction: direction)
        let row = geometry.row(of: position.midi, window: window)
        if windowCenter == nil || row < PitchMeterGeometry.edgeRows
            || row > Double(PitchMeterGeometry.rows - 1) - PitchMeterGeometry.edgeRows {
            windowCenter = position.noteMIDI
        }
    }

    private var spokenDescription: String {
        guard let position else { return "No voice detected" }
        return "\(PitchMath.noteName(midi: position.nearestNote)), \(Int(PitchMath.frequency(fromMIDI: position.midi))) hertz"
    }
}

/// Sizes from the design and where a pitch sits on the bar.
private struct PitchMeterGeometry {
    let direction: VocalPitchMeter.Direction

    /// Names on the left, the bar centred in the width.
    static let size = CGSize(width: 150, height: 196)
    static let barWidth: CGFloat = 44
    static let borderWidth: CGFloat = 4
    /// The gradient capsule sits this far inside the plum bar (draft 2.4a: 34 × 185 in 44 × 195).
    static let innerInset: CGFloat = 5
    /// Rows of names along the bar (one semitone each) and the space at the bar's ends.
    static let rows = 4
    static let rowInset: CGFloat = 11
    /// The dot may come this close (in rows) to the outer rows before the names slide.
    static let edgeRows = 0.35

    var barMinX: CGFloat { (Self.size.width - Self.barWidth) / 2 }
    var barMidX: CGFloat { Self.size.width / 2 }
    var rowPitch: CGFloat { (Self.size.height - Self.rowInset * 2) / CGFloat(Self.rows - 1) }
    /// Home row of the dot from the top: just above the bottom for the lowest note (room to go
    /// lower), just below the top for the highest.
    var homeRow: Int { direction == .lowest ? Self.rows - 2 : 1 }

    func row(of midi: Double, window: Double) -> Double { Double(homeRow) + (window - midi) }
    func y(of midi: Double, window: Double) -> CGFloat {
        let clamped = min(max(row(of: midi, window: window), 0), Double(Self.rows - 1))
        return Self.rowInset + CGFloat(clamped) * rowPitch
    }
}

private struct PitchMeterBar: View {
    let direction: VocalPitchMeter.Direction
    let geometry: PitchMeterGeometry

    var body: some View {
        Capsule().fill(Color.primaryButton)
            .overlay { Capsule().strokeBorder(Color.pitchMeterBorder.opacity(0.3), lineWidth: PitchMeterGeometry.borderWidth) }
            .overlay {
                Capsule()
                    .fill(LinearGradient(colors: direction == .lowest ? [.primaryButton, .pitchMeterGlow]
                                                                      : [.pitchMeterGlow, .primaryButton],
                                         startPoint: .top, endPoint: .bottom))
                    .padding(PitchMeterGeometry.innerInset)
            }
            .frame(width: PitchMeterGeometry.barWidth, height: PitchMeterGeometry.size.height)
            .offset(x: geometry.barMinX)
    }
}

/// The note names, animatable on `center` so they slide.
private struct PitchMeterLabels: View, Animatable {
    var center: Double
    let currentNote: Int?
    let geometry: PitchMeterGeometry
    /// Gap between a name and the bar.
    private static let labelGap: CGFloat = 4

    var animatableData: Double {
        get { center }
        set { center = newValue }
    }

    var body: some View {
        Canvas { context, _ in
            let rows = PitchMeterGeometry.rows
            let inset = PitchMeterGeometry.rowInset
            let height = PitchMeterGeometry.size.height
            for note in (Int(floor(center)) - rows)...(Int(ceil(center)) + rows) {
                let y = inset + CGFloat(Double(geometry.homeRow) + center - Double(note)) * geometry.rowPitch
                // Names fade out as they slide past the bar's ends.
                let overflow = max(inset - y, y - (height - inset), 0)
                guard overflow < geometry.rowPitch / 2 else { continue }
                var local = context
                local.opacity = 1 - Double(overflow / (geometry.rowPitch / 2))
                let current = note == currentNote
                local.draw(Text("\(PitchMath.noteName(midi: note)) -")
                            .font(.appBody.weight(current ? .bold : .regular))
                            .foregroundStyle(Color.primaryBrand),
                           at: CGPoint(x: geometry.barMinX - Self.labelGap, y: y), anchor: .trailing)
            }
        }
        .frame(width: PitchMeterGeometry.size.width, height: PitchMeterGeometry.size.height)
        .allowsHitTesting(false)
    }
}

/// The lime dot: faded while silent, growing and glowing while a note is held, popping once
/// when the note is captured.
private struct PitchMeterDot: View {
    let holdProgress: Double
    let isCaptured: Bool
    let isHearing: Bool
    let reduceMotion: Bool

    private static let size: CGFloat = 16
    private static let silentOpacity = 0.45

    var body: some View {
        let hold = min(max(holdProgress, 0), 1)
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || hold == 0)) { context in
            let pulse = reduceMotion ? 0 : 0.5 + 0.5 * sin(context.date.timeIntervalSinceReferenceDate * 2 * .pi * 2)
            ZStack {
                // Glow, stronger and wider the longer the note is held.
                Circle().fill(Color.secBrand)
                    .frame(width: Self.size * (1.6 + 0.8 * hold), height: Self.size * (1.6 + 0.8 * hold))
                    .blur(radius: 6)
                    .opacity(hold * (0.45 + 0.3 * pulse))
                Circle().fill(Color.secBrand)
                    .frame(width: Self.size, height: Self.size)
                    .scaleEffect(1 + 0.35 * hold)
            }
        }
        .opacity(isHearing || isCaptured ? 1 : Self.silentOpacity)
        .keyframeAnimator(initialValue: 1.0, trigger: isCaptured) { content, scale in
            content.scaleEffect(scale)
        } keyframes: { _ in
            if isCaptured && !reduceMotion {
                SpringKeyframe(1.7, duration: 0.18, spring: .snappy)
                SpringKeyframe(1.0, duration: 0.35, spring: .bouncy)
            } else {
                LinearKeyframe(1.0, duration: 0.01)
            }
        }
        .frame(width: Self.size * 3, height: Self.size * 3)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isHearing)
    }
}

#Preview {
    HStack(spacing: 40) {
        VocalPitchMeter(midi: 40.3, referenceMIDI: 50, direction: .lowest, holdProgress: 0.6)
        VocalPitchMeter(midi: 41, referenceMIDI: 57, direction: .highest, isCaptured: true)
    }
}
