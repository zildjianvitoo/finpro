import AVFoundation
import MediaToolbox
import Synchronization

/// One instance per composition audio track. Only the target crosses from the UI
/// to the render callback. Each channel follows the same short ramp.
nonisolated final class PreviewTrackGain: @unchecked Sendable {
    private let target: Atomic<UInt32>
    private var previous: Float
    private var format = AudioStreamBasicDescription()

    init(_ value: Float) {
        target = Atomic(value.bitPattern)
        previous = value
    }

    func set(_ value: Float) {
        target.store(value.bitPattern, ordering: .relaxed)
    }

    func makeTap() throws -> MTAudioProcessingTap {
        var callbacks = MTAudioProcessingTapCallbacks(version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passUnretained(self).toOpaque(),
            init: { _, info, storage in
                storage.pointee = Unmanaged<PreviewTrackGain>.fromOpaque(info!).retain().toOpaque()
            }, finalize: { tap in
                Unmanaged<PreviewTrackGain>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
            }, prepare: { tap, _, description in
                let gain = PreviewTrackGain.state(tap)
                gain.format = description.pointee
                gain.previous = Float(bitPattern: gain.target.load(ordering: .relaxed))
            }, unprepare: nil, process: { tap, frames, _, buffers, count, flags in
                guard MTAudioProcessingTapGetSourceAudio(tap, frames, buffers, flags, nil, count) == noErr else {
                    count.pointee = 0
                    return
                }
                PreviewTrackGain.state(tap).apply(buffers, frames: count.pointee)
            })
        var tap: MTAudioProcessingTap?
        guard MTAudioProcessingTapCreate(nil, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap) == noErr,
              let tap else { throw CompingError.exportUnavailable }
        return tap
    }

    private static func state(_ tap: MTAudioProcessingTap) -> PreviewTrackGain {
        Unmanaged<PreviewTrackGain>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    }

    private func apply(_ buffers: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        guard frames > 0 else { return }
        let value = Float(bitPattern: target.load(ordering: .relaxed))
        let ramp = max(1, min(frames, Int(format.mSampleRate * 0.005)))
        for buffer in UnsafeMutableAudioBufferListPointer(buffers) {
            guard let data = buffer.mData else { continue }
            let channels = max(1, Int(buffer.mNumberChannels))
            let bytes = Int(format.mBitsPerChannel) / 8
            guard bytes > 0 else { continue }
            let samples = min(frames * channels, Int(buffer.mDataByteSize) / bytes)
            for i in 0..<samples {
                let frame = i / channels
                let gain = frame >= ramp ? value : previous + (value - previous) * Float(frame + 1) / Float(ramp)
                if format.mFormatFlags & kAudioFormatFlagIsFloat != 0 && bytes == 4 {
                    data.assumingMemoryBound(to: Float.self)[i] *= gain
                } else if bytes == 2 {
                    let pointer = data.assumingMemoryBound(to: Int16.self)
                    pointer[i] = Int16(clamping: Int(Float(pointer[i]) * gain))
                } else if bytes == 4 {
                    let pointer = data.assumingMemoryBound(to: Int32.self)
                    pointer[i] = Int32(clamping: Int(Double(pointer[i]) * Double(gain)))
                } else if value == 0 {
                    memset(data, 0, Int(buffer.mDataByteSize))
                    break
                }
            }
        }
        previous = value
    }
}
