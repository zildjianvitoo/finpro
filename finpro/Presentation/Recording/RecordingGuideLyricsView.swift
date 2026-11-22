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
    /// Combined scale from the Pitch Guide size slider and panel resize handle (1.0 = default).
    var scale: CGFloat = 1
    /// Lines belonging to material before this time (e.g. a previous section played in pre-roll)
    /// are dimmed in grey; lines of the section being sung (including opening lyrics during
    /// countdown) stay bright white.
    var dimmedBefore: TimeInterval? = nil

    private let refreshInterval: TimeInterval = 0.1
    private let baseFontSize: CGFloat = 17
    private let glide = Animation.smooth(duration: 0.4)

    private var totalHeight: CGFloat { RecordingDisplaySettings.guideLyricsHeight * scale }
    private var rowHeight: CGFloat { totalHeight / 2 }

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
            .frame(height: totalHeight)
            .clipped()
            .frame(maxWidth: .infinity)
            .animation(glide, value: current)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(lines.indices.contains(current) ? lines[current].text : "")
        }
    }

    private func isBeforeSinging(_ line: LyricLine) -> Bool {
        guard let dimmedBefore else { return false }
        let sungEnd = line.words.last?.end ?? line.end
        return min(line.end, sungEnd) <= dimmedBefore + 1e-6
    }

    /// The current line sits on the upper row, the next one below it; others fade out.
    private func row(_ index: Int, current: Int) -> some View {
        let distance = index - current
        let opacity: Double = distance == 0 || distance == 1 ? 1 : 0
        let dimmed = isBeforeSinging(lines[index])
        return Text(lines[index].text)
            .font(.system(size: baseFontSize * scale, weight: distance == 0 ? .semibold : .regular))
            .foregroundStyle(dimmed ? Color.gray : Color.secondaryButton)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .padding(.horizontal, 12 * min(max(scale, 0.7), 1.2))
            .frame(maxWidth: .infinity)
            .frame(height: rowHeight)
            .offset(y: (CGFloat(distance) - 0.5) * rowHeight)
            .opacity(opacity)
            .animation(.easeInOut(duration: 0.2), value: dimmed)
    }
}
