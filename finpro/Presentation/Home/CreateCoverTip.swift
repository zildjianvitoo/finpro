//
//  CreateCoverTip.swift
//  finpro
//
//  TipKit tip pointing at the create button until the user makes their first cover.
//

import SwiftUI
import TipKit

struct CreateCoverTip: Tip {
    var title: Text {
        Text("Create your first cover")
    }

    var message: Text? {
        Text("Tap + to add a song and start your cover.")
    }

    var actions: [Action] {
        Action(id: "got-it", title: "Got it")
    }
}
