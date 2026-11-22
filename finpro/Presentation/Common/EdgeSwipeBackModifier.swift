//
//  EdgeSwipeBackModifier.swift
//  finpro
//
//  Left-edge interactive swipe-back gesture for screens routed by AppFlow or custom overlays
//  without a NavigationStack.
//

import SwiftUI
import UIKit

/// Invisible anchor that installs a left-edge `UIPanGestureRecognizer` directly on the owning
/// `UIViewController.view`. Attaching to the VC's view (rather than the window) ensures presented
/// sheets and alerts naturally intercept touches and never trigger the underlying screen's back.
private struct ScreenEdgeBackAnchor: UIViewRepresentable {
    let isEnabled: Bool
    let edgeWidth: CGFloat
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat, CGFloat) -> Void
    let onCancelled: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(edgeWidth: edgeWidth, onChanged: onChanged, onEnded: onEnded, onCancelled: onCancelled)
    }

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.onHostChanged = { [weak coordinator = context.coordinator] host in
            coordinator?.attach(to: host, isEnabled: isEnabled)
        }
        return view
    }

    func updateUIView(_ uiView: AnchorView, context: Context) {
        context.coordinator.edgeWidth = edgeWidth
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.onCancelled = onCancelled
        context.coordinator.setEnabled(isEnabled)
        if context.coordinator.hostView == nil, let host = uiView.owningHostView {
            context.coordinator.attach(to: host, isEnabled: isEnabled)
        }
    }

    static func dismantleUIView(_ uiView: AnchorView, coordinator: Coordinator) {
        uiView.onHostChanged = nil
        coordinator.detach()
    }

    final class AnchorView: UIView {
        var onHostChanged: ((UIView?) -> Void)?

        var owningHostView: UIView? {
            var responder: UIResponder? = self
            while let current = responder {
                if let vc = current as? UIViewController { return vc.view }
                responder = current.next
            }
            return window
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onHostChanged?(window == nil ? nil : owningHostView)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var edgeWidth: CGFloat
        var onChanged: (CGFloat) -> Void
        var onEnded: (CGFloat, CGFloat) -> Void
        var onCancelled: () -> Void
        private(set) weak var hostView: UIView?
        private var recognizer: UIPanGestureRecognizer?

        init(edgeWidth: CGFloat,
             onChanged: @escaping (CGFloat) -> Void,
             onEnded: @escaping (CGFloat, CGFloat) -> Void,
             onCancelled: @escaping () -> Void) {
            self.edgeWidth = edgeWidth
            self.onChanged = onChanged
            self.onEnded = onEnded
            self.onCancelled = onCancelled
        }

        func attach(to view: UIView?, isEnabled: Bool) {
            guard hostView !== view else {
                recognizer?.isEnabled = isEnabled
                return
            }
            detach()
            guard let view else { return }
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.maximumNumberOfTouches = 1
            pan.isEnabled = isEnabled
            pan.delegate = self
            view.addGestureRecognizer(pan)
            hostView = view
            recognizer = pan
        }

        func setEnabled(_ enabled: Bool) {
            recognizer?.isEnabled = enabled
        }

        func detach() {
            if let recognizer, let hostView {
                hostView.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
            hostView = nil
        }

        @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
            let reference = pan.view?.window ?? pan.view
            let translation = max(0, pan.translation(in: reference).x)
            let velocity = pan.velocity(in: reference).x
            switch pan.state {
            case .began, .changed:
                onChanged(translation)
            case .ended:
                onEnded(translation, velocity)
            case .cancelled, .failed:
                onCancelled()
            default:
                break
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let view = gestureRecognizer.view else { return false }
            return touch.location(in: view).x <= edgeWidth
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let view = pan.view else { return false }
            let velocity = pan.velocity(in: view)
            return velocity.x > 0 && velocity.x > abs(velocity.y) * 1.2
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            false
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // Only hold back pan/scroll gestures while evaluating a left-edge swipe, never taps.
            otherGestureRecognizer is UIPanGestureRecognizer
        }
    }
}

private struct EdgeSwipeBackModifier: ViewModifier {
    let isEnabled: Bool
    let interactiveSlide: Bool
    let edgeWidth: CGFloat
    let onProgress: ((CGFloat) -> Void)?
    let action: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var viewWidth: CGFloat = 393
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let distanceFraction: CGFloat = 0.28
    private static let maximumThreshold: CGFloat = 110
    private static let flickVelocity: CGFloat = 500
    private static let flickMinimumDistance: CGFloat = 28

    func body(content: Content) -> some View {
        let visualOffset = interactiveSlide && !reduceMotion ? dragOffset : 0
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                if width > 0 { viewWidth = width }
            }
            .shadow(color: .black.opacity(visualOffset > 0 ? 0.14 : 0), radius: 12, x: -4)
            .offset(x: visualOffset)
            .background {
                ScreenEdgeBackAnchor(
                    isEnabled: isEnabled,
                    edgeWidth: edgeWidth,
                    onChanged: { translation in
                        dragOffset = translation
                        onProgress?(min(1, max(0, translation / max(1, viewWidth))))
                    },
                    onEnded: { translation, velocity in
                        let threshold = min(viewWidth * Self.distanceFraction, Self.maximumThreshold)
                        let shouldPop = translation >= threshold
                            || (velocity >= Self.flickVelocity && translation >= Self.flickMinimumDistance)
                        if shouldPop {
                            if !interactiveSlide { dragOffset = 0 }
                            action()
                        } else {
                            snapBack()
                        }
                    },
                    onCancelled: {
                        snapBack()
                    }
                )
                .allowsHitTesting(false)
            }
            .onDisappear {
                dragOffset = 0
                onProgress?(0)
            }
    }

    private func snapBack() {
        withAnimation(reduceMotion ? nil : .spring(duration: 0.28, bounce: 0)) {
            dragOffset = 0
            onProgress?(0)
        }
    }
}

/// Parallax and subtle dimming for the screen underneath a pushed hierarchical layer,
/// matching native iOS `UINavigationController` interactive pop peeking.
private struct HierarchicalUnderlayModifier: ViewModifier {
    let isCovered: Bool
    let revealProgress: CGFloat

    @State private var viewWidth: CGFloat = 393
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let factor = isCovered ? (1 - min(1, max(0, revealProgress))) : 0
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                if width > 0 { viewWidth = width }
            }
            .offset(x: reduceMotion ? 0 : -viewWidth * 0.28 * factor)
            .overlay {
                Color.black.opacity(0.08 * factor)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            .allowsHitTesting(!isCovered)
            .accessibilityHidden(isCovered)
    }
}

extension View {
    /// Enables native-feeling left-edge swipe-back on screens that navigate via a custom back action.
    func edgeSwipeBack(isEnabled: Bool = true, interactiveSlide: Bool = true, edgeWidth: CGFloat = 24,
                       onProgress: ((CGFloat) -> Void)? = nil,
                       action: @escaping () -> Void) -> some View {
        modifier(EdgeSwipeBackModifier(isEnabled: isEnabled, interactiveSlide: interactiveSlide,
                                       edgeWidth: edgeWidth, onProgress: onProgress, action: action))
    }

    /// Applies parallax slide and subtle dim when another hierarchical screen is pushed above this view.
    func hierarchicalUnderlay(isCovered: Bool, revealProgress: CGFloat) -> some View {
        modifier(HierarchicalUnderlayModifier(isCovered: isCovered, revealProgress: revealProgress))
    }
}
