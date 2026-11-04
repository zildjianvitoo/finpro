//
//  UserFacingConvertible.swift
//  finpro
//

import Foundation

/// Data-layer errors that know how to explain themselves on screen.
nonisolated protocol UserFacingConvertible: Error {
    var userFacingError: UserFacingError { get }
}

