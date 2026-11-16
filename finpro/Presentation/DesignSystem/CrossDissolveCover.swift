//
//  CrossDissolveCover.swift
//  finpro
//
//  A full-screen cover that fades in and out with the system's cross-dissolve modal transition
//  (SwiftUI's fullScreenCover only slides up). The covered screen stays visible under a
//  translucent cover.
//

import SwiftUI
import UIKit

struct CrossDissolveCover<Cover: View>: UIViewControllerRepresentable {
    let isPresented: Bool
    @ViewBuilder let cover: Cover

    final class Coordinator {
        var presented: UIHostingController<Cover>?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        let coordinator = context.coordinator
        if isPresented {
            if let presented = coordinator.presented { presented.rootView = cover; return }
            let hosting = UIHostingController(rootView: cover)
            hosting.modalPresentationStyle = .overFullScreen
            hosting.modalTransitionStyle = .crossDissolve
            hosting.view.backgroundColor = .clear
            coordinator.presented = hosting
            // Presenting during a view update is not allowed; do it right after.
            DispatchQueue.main.async { host.present(hosting, animated: true) }
        } else if let presented = coordinator.presented {
            coordinator.presented = nil
            DispatchQueue.main.async { presented.dismiss(animated: true) }
        }
    }

    static func dismantleUIViewController(_ host: UIViewController, coordinator: Coordinator) {
        coordinator.presented?.dismiss(animated: false)
        coordinator.presented = nil
    }
}

extension View {
    /// A full-screen cover that fades in and out (system cross-dissolve).
    func crossDissolveCover<Cover: View>(isPresented: Bool, @ViewBuilder content: () -> Cover) -> some View {
        let cover = content()
        return background(CrossDissolveCover(isPresented: isPresented) { cover })
    }
}
