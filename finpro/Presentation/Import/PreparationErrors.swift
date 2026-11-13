//
//  PreparationErrors.swift
//  finpro
//
//  How song-preparation errors are explained on the import screen (PRD §9).
//

import Foundation

extension CoreMLSeparationError: UserFacingConvertible {
    var userFacingError: UserFacingError {
        switch self {
        case .drmProtected: .protectedFile
        case .unreadable, .invalidTrim: .unreadableFile
        case .modelUnavailable: .separationFailed
        }
    }
}

extension CenterChannelError: UserFacingConvertible {
    var userFacingError: UserFacingError {
        switch self {
        case .drmProtected: .protectedFile
        case .monoSource: .monoSong
        case .unreadable, .noAudioTrack, .invalidTrim: .unreadableFile
        }
    }
}
