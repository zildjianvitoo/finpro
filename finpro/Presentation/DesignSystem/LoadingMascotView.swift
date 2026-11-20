//
//  LoadingMascotView.swift
//  finpro
//
//  The loading animation for every loading state (Sketch "3rd Iteration", 6.1 Merging Clips):
//  the mascot sings into the mic, then lowers it, smiles and winks, hopping to the beat.
//

import SwiftUI

struct LoadingMascotView: View {
    /// Width and height of the square frame the artwork is drawn in (250 in the design).
    var size: CGFloat = 250
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Artwork frames: 1 sings (smiling), 2 sings (squinting), 3 smiles, 4 winks.
    private static let frames = ["LoadingMascot1", "LoadingMascot2", "LoadingMascot3", "LoadingMascot4"]
    /// Frame shown on each beat: a sung phrase, then mic down, smile, wink, smile.
    private static let sequence = [0, 1, 0, 1, 0, 1, 2, 3, 2]
    private static let beat: Double = 0.42
    /// Part of a beat the previous frame takes to fade out.
    private static let crossfade: Double = 0.12
    /// Part of a beat around each landing that is squashed.
    private static let landing: Double = 0.15
    private static let hopHeight: CGFloat = 0.04
    private static let squash: CGFloat = 0.06
    private static let swayDegrees: Double = 4
    private static let beatsPerSway: Double = 4

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let pose = Self.pose(at: reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate)
            ZStack {
                // The previous frame stays solid underneath, so the body never turns see-through.
                if pose.blend < 1 { artwork(pose.previous) }
                artwork(pose.current).opacity(pose.blend)
            }
            .scaleEffect(x: 1 + pose.squash * 2 / 3, y: 1 - pose.squash, anchor: .bottom)
            .rotationEffect(.degrees(pose.sway), anchor: .bottom)
            .offset(y: -pose.hop * size)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func artwork(_ index: Int) -> some View {
        Image(Self.frames[index]).resizable().scaledToFit()
    }

    private struct Pose {
        var previous: Int
        var current: Int
        var blend: Double
        var hop: CGFloat
        var squash: CGFloat
        var sway: Double
    }

    private static func pose(at time: TimeInterval) -> Pose {
        let beats = time / beat
        let index = Int(beats.rounded(.down))
        let progress = beats - Double(index)
        let count = sequence.count
        let current = sequence[((index % count) + count) % count]
        let previous = sequence[(((index - 1) % count) + count) % count]
        let blend = min(1, progress / crossfade)
        // One hop per beat, landing on the beat; squashed for a moment around each landing.
        let hop = CGFloat(sin(.pi * progress)) * hopHeight
        let fromGround = min(progress, 1 - progress)
        let squashAmount = CGFloat(max(0, 1 - fromGround / landing)) * squash
        let sway = sin(2 * .pi * beats / beatsPerSway) * swayDegrees
        return Pose(previous: previous, current: current, blend: blend, hop: hop, squash: squashAmount, sway: sway)
    }
}

#Preview {
    LoadingMascotView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.loadingOverlay.opacity(AppLayout.loadingOverlayOpacity))
}
