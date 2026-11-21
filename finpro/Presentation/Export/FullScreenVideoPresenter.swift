//
//  FullScreenVideoPresenter.swift
//  finpro
//
//  Shows the cover preview in the system video player, full screen, with its own controls and
//  close button. The preview's player is shared, so playback carries on where it was when the
//  player is closed.
//

import AVKit
import UIKit

enum FullScreenVideoPresenter {
    static func present(_ player: AVPlayer) {
        guard let presenter = topViewController() else { return }
        let controller = AVPlayerViewController()
        controller.player = player
        // Over the preview, not instead of it: the preview stays on screen underneath, so it is
        // not told it disappeared (which pauses the video and reloads the page).
        controller.modalPresentationStyle = .overFullScreen
        presenter.present(controller, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
