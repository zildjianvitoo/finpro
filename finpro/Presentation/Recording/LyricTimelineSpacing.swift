import Foundation

/// Extra horizontal space accumulated between adjacent word onsets.
nonisolated struct LyricTimelineSpacing {
    private struct Interval {
        let start: TimeInterval
        let end: TimeInterval
        let extra: CGFloat
    }
    private var intervals: [Interval] = []

    mutating func reserve(from start: TimeInterval, to end: TimeInterval, width: CGFloat, pointsPerSecond: CGFloat) {
        guard end > start else { return }
        let extra = width - CGFloat(end - start) * pointsPerSecond
        if extra > 0 { intervals.append(Interval(start: start, end: end, extra: extra)) }
    }

    func extra(at time: TimeInterval) -> CGFloat {
        intervals.reduce(0) { result, interval in
            let fraction = min(1, max(0, (time - interval.start) / (interval.end - interval.start)))
            return result + CGFloat(fraction) * interval.extra
        }
    }
}
