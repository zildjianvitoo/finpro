//
//  FinproApp.swift
//  finpro
//
//  Created by Zildjian Vito  on 31/10/26.
//

import SwiftUI
import TipKit

@main
struct FinproApp: App {
    @State private var flow = AppFlow(container: .makeDefault())

    init() {
        // TipKit stores which tips were shown or dismissed; a failure only means no tips.
        try? Tips.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView(flow: flow)
        }
    }
}
