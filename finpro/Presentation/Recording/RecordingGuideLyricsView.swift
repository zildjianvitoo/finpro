//
//  RecordingGuideLyricsView.swift
//  finpro
//
//  Concept 2: the lyrics inside the pitch guide panel, under the notes: the line being sung in
//  bold, the next one in regular weight. When the line changes, both glide up one row.
//

import SwiftUI

struct RecordingGuideLyricsView: View {
    let lines: [LyricLine]
    let songTime: () -> TimeInterval?

    private let refreshInterval: TimeInterval = 0.1
    private let rowHeight = RecordingDisplaySettings.guideLyricsHeight / 2
    private let glide = Animation.smooth(duration: 0.4)

    var body: some View {
        TimelineView(.periodic(from: .now, by: refreshInterval)) { _ in
            let current = lines.currentIndex(at: songTime())
            ZStack {
                ForEach(Array((current - 1)...(current + 2)), id: \.self) { index in
                    if lines.indices.contains(index) {
                        row(index, current: current)
                    }
                }
            }
            .frame(height: RecordingDisplaySettings.guideLyricsHeight)
            .clipped()
            .frame(maxWidth: .infinity)
            .animation(glide, value: current)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(lines.indices.contains(current) ? lines[current].text : "")
        }
    }

    /// The current line sits on the upper row, the next one below it; others fade out.
    private func row(_ index: Int, current: Int) -> some View {
        let distance = index - current
        let opacity: Double = distance == 0 || distance == 1 ? 1 : 0
        return Text(lines[index].text)
            .font(distance == 0 ? .appHeadline : .appHeadline.weight(.regular))
            .foregroundStyle(Color.secondaryButton)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: rowHeight)
            .offset(y: (CGFloat(distance) - 0.5) * rowHeight)
            .opacity(opacity)
    }
}
