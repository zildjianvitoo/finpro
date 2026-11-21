//
//  ObservationScope.swift
//  finpro
//
//  Builds its content in its own body, so the @Observable values read there redraw only this
//  part, not the whole screen around it. For parts that follow a fast-changing value, like the
//  cover preview's pitch guide and seek bar following the playing time ten times a second.
//

import SwiftUI

struct ObservationScope<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View { content() }
}
