//
//  SpeechTranscriberWordRecognition.swift
//  finpro
//
//  Recognizes the words sung in the vocal stem with Apple's on-device SpeechTranscriber (iOS 26+),
//  so the lyric guide can put words where they are sung. Picks the language from the lyrics; a
//  language without an on-device model (Indonesian, as of iOS 26), an older iOS, or any failure
//  gives no words and the guide falls back to placing them from the pitch notes alone.
//  Owner: Zildjian Vito.
//

import AVFoundation
import Foundation
import NaturalLanguage
import OSLog
import Speech

nonisolated struct SpeechTranscriberWordRecognition: SungWordRecognitionRepository {
    /// The language model is downloaded once; preparation doesn't wait longer than this for it.
    var modelDownloadLimit: Duration = .seconds(20)

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "finpro", category: "WordRecognition")

    func recognizeWords(in vocalGuideURL: URL, lyrics: String) async -> [RecognizedWord] {
        guard #available(iOS 26.0, *) else { return [] }
        return await Self.recognize(vocalGuideURL, lyrics: lyrics, downloadLimit: modelDownloadLimit)
    }

    @available(iOS 26.0, *)
    private static func recognize(_ url: URL, lyrics: String, downloadLimit: Duration) async -> [RecognizedWord] {
        guard SpeechTranscriber.isAvailable else {
            log.notice("speech transcription unavailable on this device")
            return []
        }
        let languageRecognizer = NLLanguageRecognizer()
        languageRecognizer.processString(lyrics)
        guard let language = languageRecognizer.dominantLanguage,
              let locale = await supportedLocale(for: language.rawValue) else {
            log.notice("no on-device recognizer for the lyrics' language")
            return []
        }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [],
                                            attributeOptions: [.audioTimeRange])
        do {
            // An app may keep models for only a few languages: make room for this one if needed.
            let reserved = await AssetInventory.reservedLocales
            if !reserved.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) {
                if reserved.count >= AssetInventory.maximumReservedLocales, let oldest = reserved.first {
                    _ = await AssetInventory.release(reservedLocale: oldest)
                }
                _ = try await AssetInventory.reserve(locale: locale)
            }
            // The simulator and some devices have no transcription model at all.
            guard await AssetInventory.status(forModules: [transcriber]) != .unsupported else {
                log.notice("speech transcription unsupported on this device")
                return []
            }
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                // The download goes on after the limit (it is not cancelled with the wait), so the
                // model is ready for the next song prepared.
                let download = Task.detached { () -> Bool in
                    do {
                        try await request.downloadAndInstall()
                        log.notice("speech model for \(locale.identifier, privacy: .public) installed")
                        return true
                    } catch {
                        log.error("speech model download failed: \(error.localizedDescription, privacy: .public)")
                        return false
                    }
                }
                let installed = await withTaskGroup(of: Bool.self) { group in
                    group.addTask { await download.value }
                    group.addTask { try? await Task.sleep(for: downloadLimit); return false }
                    let first = await group.next() ?? false
                    group.cancelAll()
                    return first
                }
                guard installed else {
                    log.notice("speech model for \(locale.identifier, privacy: .public) not ready")
                    return []
                }
            }
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let file = try AVAudioFile(forReading: url)
            let collect = Task { () -> [RecognizedWord] in
                var words: [RecognizedWord] = []
                for try await result in transcriber.results {
                    for run in result.text.runs {
                        guard let range = run.audioTimeRange else { continue }
                        let text = String(result.text[run.range].characters).trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { continue }
                        words.append(RecognizedWord(text: text, startTime: range.start.seconds, endTime: range.end.seconds))
                    }
                }
                return words
            }
            if let last = try await analyzer.analyzeSequence(from: file) {
                try await analyzer.finalizeAndFinish(through: last)
            } else {
                await analyzer.cancelAndFinishNow()
            }
            let words = try await collect.value.sorted { $0.startTime < $1.startTime }
            log.notice("recognized \(words.count, privacy: .public) words (\(locale.identifier, privacy: .public))")
            return words
        } catch {
            log.error("word recognition failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// The transcriber locale for a language code ("en"), trying the device's region first.
    @available(iOS 26.0, *)
    private static func supportedLocale(for language: String) async -> Locale? {
        let region = Locale.current.region?.identifier
        let candidates = [region.map { "\(language)-\($0)" }, language, "\(language)-US"].compactMap { $0 }
        for identifier in candidates {
            if let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: identifier)) {
                return locale
            }
        }
        return nil
    }
}
