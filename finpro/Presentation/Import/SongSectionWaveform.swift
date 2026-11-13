//
//  SongSectionWaveform.swift
//  finpro
//
//  The clip picker works like Instagram's music picker: the selection box stays in the middle and
//  the waveform scrolls under it. Dragging anywhere (inside or outside the box) scrolls the song;
//  the box edges change the clip length.
//

import SwiftUI

struct SongSectionWaveform: View {
    enum Style { case clip, library }
    @Bindable var viewModel: ImportSongViewModel
    let audio: ImportedAudio
    var style: Style = .clip
    /// The selection when the current drag began.
    @State private var origin: (start: TimeInterval, length: TimeInterval)?
    /// While an edge is dragged, the box stays where it was (so the edge follows the finger):
    /// the song time and x position of the box's leading edge at the start of the drag.
    @State private var resizeAnchor: (time: TimeInterval, x: CGFloat)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var barCount: Int { style == .clip ? 32 : 48 }
    private var visibleSeconds: TimeInterval { viewModel.waveformVisibleSeconds }
    private var barSeconds: TimeInterval { visibleSeconds / Double(barCount) }
    private var selectionEnd: TimeInterval { viewModel.selectionStart + viewModel.selectionLength }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let scale = width / visibleSeconds
            let start = x(viewModel.selectionStart, width: width, scale: scale)
            let end = x(selectionEnd, width: width, scale: scale)
            let played = x(viewModel.playbackTime ?? viewModel.selectionStart, width: width, scale: scale)
            ZStack(alignment: .leading) {
                Color.clear.contentShape(Rectangle())
                RoundedRectangle(cornerRadius: AppRadius.extraSmall)
                    .fill(style == .library ? Color.primary800.opacity(0.4) : Color.secondary300.opacity(0.6))
                    .frame(width: max(0, end - start)).offset(x: start)
                RoundedRectangle(cornerRadius: AppRadius.extraSmall)
                    .fill(style == .library ? Color.primaryBrand.opacity(0.4) : Color.secBrand)
                    .frame(width: max(0, min(end, played) - start)).offset(x: start)
                bars(width: width, height: proxy.size.height, scale: scale)
                RoundedRectangle(cornerRadius: AppRadius.extraSmall)
                    .stroke(Color.primary800, lineWidth: 2)
                    .frame(width: max(0, end - start)).offset(x: start)
                    .allowsHitTesting(false)
                handle(at: start, width: width, scale: scale, leading: true)
                handle(at: end, width: width, scale: scale, leading: false)
            }
            .clipped()
            .contentShape(Rectangle())
            .gesture(scroll(scale: scale))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Song waveform, \(Int(viewModel.selectionLength)) seconds selected")
        .accessibilityAdjustableAction { direction in
            viewModel.beginSelectionEditing()
            viewModel.selectionStart = clampedStart(viewModel.selectionStart + (direction == .increment ? 5 : -5),
                                                    length: viewModel.selectionLength)
            viewModel.endSelectionEditing()
        }
    }

    // MARK: Layout

    /// x of a song time. The box is centered, except while an edge is dragged.
    private func x(_ time: TimeInterval, width: CGFloat, scale: CGFloat) -> CGFloat {
        if let resizeAnchor { return resizeAnchor.x + CGFloat(time - resizeAnchor.time) * scale }
        let boxX = (width - CGFloat(viewModel.selectionLength) * scale) / 2
        return boxX + CGFloat(time - viewModel.selectionStart) * scale
    }

    /// Bars at fixed song times, so they slide with the song instead of changing shape.
    private func bars(width: CGFloat, height: CGFloat, scale: CGFloat) -> some View {
        let total = Int((audio.duration / barSeconds).rounded(.up))
        let first = max(0, Int(((viewModel.selectionStart - visibleSeconds) / barSeconds).rounded(.down)))
        let last = min(total, Int(((selectionEnd + visibleSeconds) / barSeconds).rounded(.up)))
        let barWidth: CGFloat = style == .clip ? 6 : 4
        return ZStack(alignment: .leading) {
            ForEach(first..<max(first, last), id: \.self) { index in
                let time = (Double(index) + 0.5) * barSeconds
                let inside = time >= viewModel.selectionStart && time <= selectionEnd
                Capsule()
                    .fill(style == .library ? Color.primary100 : inside ? Color.primaryBrand : Color.primary300)
                    .frame(width: barWidth, height: max(4, CGFloat(level(at: time)) * height * 0.85))
                    .offset(x: x(time, width: width, scale: scale) - barWidth / 2)
            }
        }
        .frame(width: width, height: height, alignment: .leading)
        .allowsHitTesting(false)
    }

    private func level(at time: TimeInterval) -> Float {
        guard !audio.waveform.isEmpty, audio.duration > 0 else { return 0 }
        let perSecond = Double(audio.waveform.count) / audio.duration
        let lower = min(audio.waveform.count - 1, max(0, Int(time * perSecond)))
        let upper = min(audio.waveform.count, max(lower + 1, Int((time + barSeconds) * perSecond)))
        return audio.waveform[lower..<upper].max() ?? 0
    }

    // MARK: Gestures

    private func begin() -> (start: TimeInterval, length: TimeInterval) {
        viewModel.beginSelectionEditing()
        if let origin { return origin }
        let value = (viewModel.selectionStart, viewModel.selectionLength)
        origin = value
        return value
    }

    private func end() {
        origin = nil
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { resizeAnchor = nil }
        viewModel.endSelectionEditing()
    }

    private func clampedStart(_ start: TimeInterval, length: TimeInterval) -> TimeInterval {
        min(max(0, start), max(0, audio.duration - length))
    }

    /// Drag the waveform like a strip of film: to the left goes later in the song.
    private func scroll(scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let initial = begin()
                let delta = TimeInterval(value.translation.width / max(1, scale))
                viewModel.selectionStart = clampedStart(initial.start - delta, length: initial.length)
            }
            .onEnded { _ in end() }
    }

    private func handle(at position: CGFloat, width: CGFloat, scale: CGFloat, leading: Bool) -> some View {
        Capsule().fill(Color.primary800).frame(width: 3)
            .frame(width: 28).contentShape(Rectangle()).offset(x: position - 14)
            .highPriorityGesture(DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let initial = begin()
                    if resizeAnchor == nil {
                        resizeAnchor = (initial.start, x(initial.start, width: width, scale: scale))
                    }
                    let delta = TimeInterval(value.translation.width / max(1, scale))
                    resize(from: initial, by: delta, leading: leading)
                }
                .onEnded { _ in end() })
            .accessibilityLabel(leading ? "Selection start" : "Selection end")
            .accessibilityValue("\(Int(leading ? viewModel.selectionStart : selectionEnd)) seconds")
            .accessibilityAdjustableAction { direction in
                viewModel.beginSelectionEditing()
                resize(from: (viewModel.selectionStart, viewModel.selectionLength),
                       by: direction == .increment ? 1 : -1, leading: leading)
                viewModel.endSelectionEditing()
            }
    }

    /// Moves one edge, keeping the length within 15–60 s and the clip inside the song.
    private func resize(from initial: (start: TimeInterval, length: TimeInterval), by delta: TimeInterval, leading: Bool) {
        if leading {
            let finish = initial.start + initial.length
            let start = min(max(max(0, finish - ImportSongViewModel.maximumLength), initial.start + delta),
                            finish - ImportSongViewModel.minimumLength)
            viewModel.selectionStart = start
            viewModel.selectionLength = finish - start
        } else {
            viewModel.selectionLength = min(max(ImportSongViewModel.minimumLength, initial.length + delta),
                                            min(ImportSongViewModel.maximumLength, audio.duration - initial.start))
        }
    }
}
