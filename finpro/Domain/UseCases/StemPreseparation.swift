//
//  StemPreseparation.swift
//  finpro
//
//  Optional capability: warms the chunk cache for a song section in the background while the user
//  is still on the trim screen, so preparation finishes faster when they continue.
//

import Foundation

nonisolated protocol StemPreseparation: StemSeparationRepository {
    func preseparate(audioURL: URL, trimRange: ClosedRange<TimeInterval>, leadInDuration: TimeInterval) async
}
