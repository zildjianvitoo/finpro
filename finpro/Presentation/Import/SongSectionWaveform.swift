//
//  SongSectionWaveform.swift
//  finpro
//

import SwiftUI

struct SongSectionWaveform: View {
    enum Style { case clip, library }
    @Bindable var viewModel: ImportSongViewModel
    let audio: ImportedAudio
    var style: Style = .clip
    @State private var origin: (start: TimeInterval, length: TimeInterval)?
    @State private var dragInterval: ClosedRange<TimeInterval>?
    private var interval: ClosedRange<TimeInterval> { dragInterval ?? viewModel.waveformInterval }
    private var span: TimeInterval { max(1, interval.upperBound - interval.lowerBound) }
    private var count: Int { style == .clip ? 32 : 48 }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let start = x(viewModel.selectionStart, width)
            let end = x(viewModel.selectionStart + viewModel.selectionLength, width)
            let played = x(viewModel.playbackTime ?? viewModel.selectionStart, width)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: AppRadius.extraSmall)
                    .fill(style == .library ? Color.secondaryText.opacity(0.6) : .clear)
                    .contentShape(Rectangle()).gesture(move(width))
                RoundedRectangle(cornerRadius: AppRadius.extraSmall)
                    .fill(style == .library ? Color.primary800.opacity(0.4) : Color.secondary300.opacity(0.6))
                    .frame(width: max(0, end - start)).offset(x: start)
                RoundedRectangle(cornerRadius: AppRadius.extraSmall)
                    .fill(style == .library ? Color.primaryBrand.opacity(0.4) : Color.secBrand)
                    .frame(width: max(0, min(end, played) - start)).offset(x: start)
                HStack(spacing: 0) {
                    ForEach(0..<count, id: \.self) { index in
                        let inside = isSelected(index)
                        Capsule().fill(style == .library ? Color.primary100 : inside ? Color.primaryBrand : Color.primary300)
                            .frame(width: style == .clip ? 6 : 4,
                                   height: max(4, CGFloat(level(index)) * proxy.size.height * 0.85))
                            .frame(width: width / CGFloat(count))
                    }
                }
                .allowsHitTesting(false)
                RoundedRectangle(cornerRadius: AppRadius.extraSmall)
                    .stroke(Color.primary800, lineWidth: 2)
                    .frame(width: max(0, end - start)).offset(x: start)
                    .contentShape(Rectangle()).gesture(move(width))
                handle(start, width, leading: true)
                handle(end, width, leading: false)
            }
            .clipped()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Song waveform, \(Int(viewModel.selectionLength)) seconds selected")
    }
    private func begin() -> (start: TimeInterval, length: TimeInterval) {
        viewModel.beginSelectionEditing()
        if let origin { return origin }
        dragInterval = viewModel.waveformInterval
        let value = (viewModel.selectionStart, viewModel.selectionLength)
        origin = value
        return value
    }
    private func end() {
        origin = nil; dragInterval = nil
        viewModel.endSelectionEditing()
    }
    private func handle(_ position: CGFloat, _ width: CGFloat, leading: Bool) -> some View {
        Capsule().fill(Color.primary800).frame(width: 3)
            .frame(width: 28).contentShape(Rectangle()).offset(x: position - 14)
            .gesture(DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let initial = begin()
                    let delta = seconds(value.translation.width, width)
                    if leading {
                        let finish = initial.start + initial.length
                        let start = min(max(max(0, finish - ImportSongViewModel.maximumLength), initial.start + delta),
                                        finish - ImportSongViewModel.minimumLength)
                        viewModel.selectionStart = start
                        viewModel.selectionLength = finish - start
                    } else { viewModel.selectionLength = initial.length + delta }
                }
                .onEnded { _ in end() })
            .accessibilityLabel(leading ? "Selection start" : "Selection end")
            .accessibilityValue("\(Int(leading ? viewModel.selectionStart : viewModel.selectionStart + viewModel.selectionLength)) seconds")
            .accessibilityAdjustableAction { direction in
                viewModel.beginSelectionEditing()
                let step: Double = direction == .increment ? 1 : -1
                if leading {
                    let finish = viewModel.selectionStart + viewModel.selectionLength
                    let start = min(max(max(0, finish - ImportSongViewModel.maximumLength), viewModel.selectionStart + step),
                                    finish - ImportSongViewModel.minimumLength)
                    viewModel.selectionStart = start
                    viewModel.selectionLength = finish - start
                } else { viewModel.selectionLength += step }
                viewModel.endSelectionEditing()
            }
    }
    private func move(_ width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let initial = begin()
                viewModel.selectionStart = min(max(0, initial.start + seconds(value.translation.width, width)),
                                               max(0, audio.duration - initial.length))
                viewModel.selectionLength = initial.length
            }
            .onEnded { _ in end() }
    }
    private func x(_ time: Double, _ width: CGFloat) -> CGFloat { width * (time - interval.lowerBound) / span }
    private func seconds(_ distance: CGFloat, _ width: CGFloat) -> Double { Double(distance / max(1, width)) * span }
    private func time(_ index: Int) -> TimeInterval { interval.lowerBound + (Double(index) + 0.5) / Double(count) * span }
    private func isSelected(_ index: Int) -> Bool {
        let time = time(index)
        return time >= viewModel.selectionStart && time <= viewModel.selectionStart + viewModel.selectionLength
    }
    private func level(_ index: Int) -> Float {
        guard !audio.waveform.isEmpty else { return 0 }
        let center = min(audio.waveform.count - 1, max(0, Int(time(index) / max(1, audio.duration) * Double(audio.waveform.count))))
        let bins = max(1, Int(span / max(1, audio.duration) * Double(audio.waveform.count) / Double(count)))
        return audio.waveform[center..<min(audio.waveform.count, center + bins)].max() ?? 0
    }
}
