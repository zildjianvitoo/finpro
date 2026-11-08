//
//  RecordingLyricsView.swift
//  finpro
//
//  Teleprompter near the camera on the recording screen: the previous, current and next lyric
//  lines, the current one highlighted. Follows the same song time as the pitch guide.
//

import SwiftUI

struct RecordingLyricsView: View {
    let lines: [LyricLine]
    let songTime: () -> TimeInterval?
    /// Opacity of the dark panel (a display setting).
    var backgroundOpacity = RecordingDisplaySettings.defaultLyricsOpacity
    var isPaused = false

    private let refreshInterval: TimeInterval = 0.1
    private let cornerRadius: CGFloat = 12

    var body: some View {
        TimelineView(.periodic(from: .now, by: refreshInterval)) { _ in
            let current = currentIndex(at: songTime())
            VStack(spacing: 4) {
                line(at: current - 1, isCurrent: false)
                line(at: current, isCurrent: true)
                line(at: current + 1, isCurrent: false)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(.black.opacity(backgroundOpacity), in: .rect(cornerRadius: cornerRadius))
            .animation(.easeInOut(duration: 0.25), value: current)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(lines.indices.contains(current) ? lines[current].text : "")
        }
    }

    @ViewBuilder
    private func line(at index: Int, isCurrent: Bool) -> some View {
        let text = lines.indices.contains(index) ? lines[index].text : " "
        Text(text)
            .font(.footnote.weight(isCurrent ? .semibold : .regular))
            .foregroundStyle(isCurrent ? Color.white : Color.white.opacity(0.6))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background {
                if isCurrent {
                    Capsule().fill(.black.opacity(0.45))
                }
            }
    }

    /// The line being sung, or the next one before it starts.
    private func currentIndex(at time: TimeInterval?) -> Int {
        guard let time else { return 0 }
        return lines.lastIndex { $0.start <= time } ?? 0
    }
}
