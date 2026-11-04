//
//  HeadsetMicrophoneErrors.swift
//  finpro
//

import Foundation

extension HeadsetMicrophoneError: UserFacingConvertible {
    var userFacingError: UserFacingError { .headsetMicrophoneRequired }
}
