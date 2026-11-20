import AVFoundation
import MediaToolbox
import Synchronization

/// One instance per composition audio track. Only the target crosses from the UI
/// to the render callback. Each channel follows the same short ramp.
/// The track's crossfades and fade-out (`envelope`) are applied here from the source time too, not
/// as audio mix ramps, which AVPlayer can leave at 0 after looping or seeking.
nonisolated final class PreviewTrackGain: @unchecked Sendable {
    private let target: Atomic<UInt32>
    private var previous: Float
    private var format = AudioStreamBasicDescription()
    private let envelope: PreviewEnvelope
    /// Per-frame gains of the buffer being processed, sized in `prepare` (no allocation while rendering).
    private var gains: UnsafeMutablePointer<Float>?
    private var gainCapacity = 0
    /// Where the next buffer starts when the source reports no time.
    private var nextTime: TimeInterval = 0

    init(_ value: Float, envelope: PreviewEnvelope) {
        target = Atomic(value.bitPattern)
        previous = value
        self.envelope = envelope
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
            }, prepare: { tap, maxFrames, description in
                let gain = PreviewTrackGain.state(tap)
                gain.format = description.pointee
                gain.previous = Float(bitPattern: gain.target.load(ordering: .relaxed))
                gain.gains?.deallocate()
                gain.gainCapacity = Int(maxFrames)
                gain.gains = .allocate(capacity: max(1, gain.gainCapacity))
            }, unprepare: { tap in
                let gain = PreviewTrackGain.state(tap)
                gain.gains?.deallocate()
                gain.gains = nil
                gain.gainCapacity = 0
            }, process: { tap, frames, _, buffers, count, flags in
                var range = CMTimeRange.invalid
                guard MTAudioProcessingTapGetSourceAudio(tap, frames, buffers, flags, &range, count) == noErr else {
                    count.pointee = 0
                    return
                }
                PreviewTrackGain.state(tap).apply(buffers, frames: count.pointee, start: range.start)
            })
        var tap: MTAudioProcessingTap?
        guard MTAudioProcessingTapCreate(nil, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap) == noErr,
              let tap else { throw CompingError.exportUnavailable }
        return tap
    }

    private static func state(_ tap: MTAudioProcessingTap) -> PreviewTrackGain {
        Unmanaged<PreviewTrackGain>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    }

    private func apply(_ buffers: UnsafeMutablePointer<AudioBufferList>, frames: Int, start: CMTime) {
        guard frames > 0, let gains, frames <= gainCapacity else { return }
        let value = Float(bitPattern: target.load(ordering: .relaxed))
        let rate = format.mSampleRate > 0 ? format.mSampleRate : 48_000
        let ramp = max(1, min(frames, Int(rate * 0.005)))
        let time = start.isNumeric ? start.seconds : nextTime
        for frame in 0..<frames {
            let slider = frame >= ramp ? value : previous + (value - previous) * Float(frame + 1) / Float(ramp)
            gains[frame] = slider * envelope.gain(at: time + Double(frame) / rate)
        }
        nextTime = time + Double(frames) / rate
        for buffer in UnsafeMutableAudioBufferListPointer(buffers) {
            guard let data = buffer.mData else { continue }
            let channels = max(1, Int(buffer.mNumberChannels))
            let bytes = Int(format.mBitsPerChannel) / 8
            guard bytes > 0 else { continue }
            let samples = min(frames * channels, Int(buffer.mDataByteSize) / bytes)
            for i in 0..<samples {
                let gain = gains[i / channels]
                if format.mFormatFlags & kAudioFormatFlagIsFloat != 0 && bytes == 4 {
                    data.assumingMemoryBound(to: Float.self)[i] *= gain
                } else if bytes == 2 {
                    let pointer = data.assumingMemoryBound(to: Int16.self)
                    pointer[i] = Int16(clamping: Int(Float(pointer[i]) * gain))
                } else if bytes == 4 {
                    let pointer = data.assumingMemoryBound(to: Int32.self)
                    pointer[i] = Int32(clamping: Int(Double(pointer[i]) * Double(gain)))
                } else {
                    memset(data, 0, Int(buffer.mDataByteSize))
                    break
                }
            }
        }
        previous = value
    }

    deinit { gains?.deallocate() }
}
