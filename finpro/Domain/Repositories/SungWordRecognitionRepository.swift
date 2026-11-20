//
//  SungWordRecognitionRepository.swift
//  finpro
//
//  CONTRACT — owned by the whole team. See docs/COLLABORATION.md before editing.
//  Added 2026-11-20 with the user's OK. Implemented by: Zildjian Vito.
//

import Foundation

nonisolated protocol SungWordRecognitionRepository: Sendable {
    /// Words heard in the (already trimmed) vocal stem, sorted by `startTime`. `lyrics` is the text
    /// sung there, used to pick the language. Returns an empty list when the language, the OS or the
    /// device has no on-device recognizer, or anything fails: the guide then places the words
    /// without it, so this never throws.
    func recognizeWords(in vocalGuideURL: URL, lyrics: String) async -> [RecognizedWord]
}
