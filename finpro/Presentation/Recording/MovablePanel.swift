//
//  MovablePanel.swift
//  finpro
//
//  A panel the user can move by a grab bar above it and resize by a handle at its bottom-right
//  corner (the pitch guide on the recording screen). Taps inside the panel never move it, so
//  touching it while singing is safe. Frames are in the coordinates of the view it floats over;
//  the panel stays inside `bounds`.
//

import SwiftUI

struct MovablePanel<Content: View>: View {
    /// Where the panel sits until the user moves or resizes it.
    let defaultFrame: CGRect
    /// The area the panel must stay in.
    let bounds: CGRect
    let minimumSize: CGSize
    /// The user's frame, nil for `defaultFrame`; set when a drag ends.
    @Binding var frame: CGRect?
    @ViewBuilder let content: (CGSize) -> Content

    @GestureState private var moving: CGSize = .zero
    @GestureState private var resizing: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let handleHitSize: CGFloat = 44

    var body: some View {
        let shown = clamped(current)
        content(shown.size)
            .frame(width: shown.width, height: shown.height)
            .overlay(alignment: .top) { grabBar }
            .overlay(alignment: .bottomTrailing) { resizeHandle }
            .position(x: shown.midX, y: shown.midY)
            .accessibilityAction(named: "Reset pitch guide position") { frame = nil }
    }

    private var current: CGRect {
        let base = frame ?? defaultFrame
        return CGRect(x: base.minX + moving.width, y: base.minY + moving.height,
                      width: base.width + resizing.width, height: base.height + resizing.height)
    }

    /// Size within the minimum and the bounds, then position inside the bounds.
    private func clamped(_ rect: CGRect) -> CGRect {
        let width = min(max(minimumSize.width, rect.width), bounds.width)
        let height = min(max(minimumSize.height, rect.height), bounds.height)
        let x = min(max(bounds.minX, rect.minX), bounds.maxX - width)
        let y = min(max(bounds.minY, rect.minY), bounds.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private var grabBar: some View {
        Capsule()
            .fill(.white.opacity(0.85))
            .frame(width: 40, height: 5)
            .shadow(color: .black.opacity(0.3), radius: 2)
            .frame(width: 88, height: 28)
            .contentShape(Rectangle())
            .offset(y: -22)
            .gesture(DragGesture(minimumDistance: 2)
                .updating($moving) { value, state, _ in state = value.translation }
                .onEnded { value in
                    let base = frame ?? defaultFrame
                    frame = clamped(base.offsetBy(dx: value.translation.width, dy: value.translation.height))
                })
            .accessibilityLabel("Move pitch guide")
            .accessibilityHint("Drag to move the pitch guide")
    }

    private var resizeHandle: some View {
        // A quarter circle hugging the panel's rounded corner, like a resizable window.
        Path { path in
            path.addArc(center: CGPoint(x: 6, y: 6), radius: 14, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        }
        .stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        .shadow(color: .black.opacity(0.3), radius: 2)
        .frame(width: 20, height: 20)
        .frame(width: handleHitSize, height: handleHitSize, alignment: .topLeading)
        .contentShape(Rectangle())
        .offset(x: 18, y: 18)
        .gesture(DragGesture(minimumDistance: 2)
            .updating($resizing) { value, state, _ in state = value.translation }
            .onEnded { value in
                let base = frame ?? defaultFrame
                frame = clamped(CGRect(origin: base.origin, size: CGSize(width: base.width + value.translation.width,
                                                                        height: base.height + value.translation.height)))
            })
        .accessibilityLabel("Resize pitch guide")
        .accessibilityHint("Drag to make the pitch guide bigger or smaller")
    }
}
