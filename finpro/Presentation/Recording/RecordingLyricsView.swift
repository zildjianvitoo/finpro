//
//  RecordingLyricsView.swift
//  finpro
//
//  Concept 1: the lyrics card near the camera on the recording screen. The previous, current and
//  next line, the current one on a lime capsule that stays in place while the lines glide up
//  (like the lyrics of a song in a story), with a text size button and a hide button.
//  Follows the same song time as the pitch guide.
//

import SwiftUI

struct RecordingLyricsView: View {
    let lines: [LyricLine]
    let songTime: () -> TimeInterval?
    /// Index into `RecordingDisplaySettings.lyricsTextStyles`.
    let textStep: Int
    let onChangeTextSize: () -> Void
    let onHide: () -> Void

    private let refreshInterval: TimeInterval = 0.1
    private let cornerRadius: CGFloat = AppRadius.large - 4
    private let topInset: CGFloat = 20
    private let bottomInset: CGFloat = 8
    private let rowHeight: CGFloat = 28
    /// Extra row height per text size step, so larger text keeps its air.
    private let rowGrowth: CGFloat = 3
    private let highlightHeight: CGFloat = 32
    private let highlightInset: CGFloat = 20
    private let textInset: CGFloat = 28
    private let glide = Animation.smooth(duration: 0.4)

    var body: some View {
        TimelineView(.periodic(from: .now, by: refreshInterval)) { _ in
            let current = lines.currentIndex(at: songTime())
            ZStack {
                Capsule()
                    .fill(Color.secBrand)
                    .frame(height: highlightHeight + rowGrowth * CGFloat(textStep))
                    .padding(.horizontal, highlightInset)

                ForEach(Array((current - 2)...(current + 2)), id: \.self) { index in
                    if lines.indices.contains(index) {
                        row(index, current: current)
                    }
                }
            }
            .frame(height: rowSize * 3)
            .clipped()
            .padding(.top, topInset)
            .padding(.bottom, bottomInset)
            .frame(maxWidth: .infinity)
            .background(Color.secondaryButton.opacity(0.4), in: .rect(cornerRadius: cornerRadius, style: .continuous))
            .overlay(alignment: .topLeading) { cornerButton("textformat.size", label: "Lyrics text size", action: onChangeTextSize) }
            .overlay(alignment: .topTrailing) { cornerButton("xmark", label: "Hide lyrics", action: onHide) }
            .animation(glide, value: current)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(lines.indices.contains(current) ? lines[current].text : "")
        }
    }

    private var rowSize: CGFloat { rowHeight + rowGrowth * CGFloat(textStep) }

    /// A line sits `index - current` rows from the middle; the ones beyond the neighbours fade out.
    private func row(_ index: Int, current: Int) -> some View {
        let distance = index - current
        return Text(lines[index].text)
            .font(RecordingDisplaySettings.lyricsTextStyle(step: textStep).weight(.semibold))
            .foregroundStyle(distance == 0 ? Color.primary800 : Color.primaryBrand.opacity(0.8))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, textInset)
            .frame(maxWidth: .infinity)
            .frame(height: rowSize)
            .offset(y: CGFloat(distance) * rowSize)
            .opacity(abs(distance) <= 1 ? 1 : 0)
    }

    private func cornerButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.callout.weight(.bold))
                .foregroundStyle(Color.primary800)
                .frame(width: 44, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
