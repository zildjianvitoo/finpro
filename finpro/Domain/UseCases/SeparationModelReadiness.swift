//
//  SeparationModelReadiness.swift
//  finpro
//
//  Optional capability: tells whether the separation model has finished its first run in this
//  app launch. The first run compiles the model for the device (about 25 s on an iPhone 17 right
//  after install), so the preparing screen can say the model is still getting ready.
//

import Foundation

nonisolated protocol SeparationModelReadiness: StemSeparationRepository {
    /// False until the model has finished one run since the app opened.
    var isModelReady: Bool { get }
}
