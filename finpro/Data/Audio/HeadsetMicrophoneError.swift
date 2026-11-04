//
//  HeadsetMicrophoneError.swift
//  finpro
//

import Foundation

nonisolated enum HeadsetMicrophoneError: Error {
    case unavailable
}

extension Notification.Name {
    nonisolated static let headsetMicrophoneChanged = Notification.Name("HeadsetMicrophoneChanged")
}
