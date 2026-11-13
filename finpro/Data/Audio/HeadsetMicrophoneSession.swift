//
//  HeadsetMicrophoneSession.swift
//  finpro
//

import AVFoundation

nonisolated enum HeadsetMicrophoneSession {
    static func kind(of port: AVAudioSession.Port) -> SelectHeadsetMicrophoneUseCase.InputKind {
        switch port {
        case .headsetMic: .wiredHeadset
        case .usbAudio: .usb
        case .bluetoothHFP, .bluetoothLE: .bluetooth
        default: .unsupported
        }
    }

    /// Debug only (`DebugOptions.allowsSpeakerRecording`): without a headset, the built-in
    /// microphone is used instead of failing.
    private static var allowsBuiltInMicrophone: Bool { DebugOptions.allowsSpeakerRecording }

    static var currentInput: AVAudioSessionPortDescription? {
        let inputs = AVAudioSession.sharedInstance().currentRoute.inputs
        return inputs.first { kind(of: $0.portType) != .unsupported } ?? (allowsBuiltInMicrophone ? inputs.first : nil)
    }

    /// HFP is needed for Bluetooth microphone input; A2DP alone provides output only.
    @discardableResult
    static func activate(mode: AVAudioSession.Mode, sampleRate: Double? = nil) throws -> String {
        let session = AVAudioSession.sharedInstance()
        var options: AVAudioSession.CategoryOptions = [.allowBluetoothA2DP, .allowBluetoothHFP]
        // Without earphones the song must come out of the loudspeaker, not the quiet receiver.
        if allowsBuiltInMicrophone { options.insert(.defaultToSpeaker) }
        try session.setCategory(.playAndRecord, mode: mode, options: options)
        if let sampleRate { try session.setPreferredSampleRate(sampleRate) }
        try session.setActive(true)
        do {
            let inputs = session.availableInputs ?? []
            let headset = SelectHeadsetMicrophoneUseCase().execute(inputs.map { kind(of: $0.portType) }).map { inputs[$0] }
            let builtIn = allowsBuiltInMicrophone ? (inputs.first { $0.portType == .builtInMic } ?? inputs.first) : nil
            guard let microphone = headset ?? builtIn else {
                throw HeadsetMicrophoneError.unavailable
            }
            try session.setPreferredInput(microphone)
            return microphone.uid
        } catch {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw error
        }
    }

    static func verify(_ selectedUID: String) throws {
        guard currentInput?.uid == selectedUID else { throw HeadsetMicrophoneError.unavailable }
    }
}
