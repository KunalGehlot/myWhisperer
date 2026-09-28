import Foundation

/// A recorded utterance: 16-bit mono PCM.
public struct AudioClip: Sendable, Equatable {
    public var samples: [Int16]
    public var sampleRate: Int

    public init(samples: [Int16], sampleRate: Int = 16_000) {
        self.samples = samples
        self.sampleRate = sampleRate
    }

    public var duration: Double {
        sampleRate > 0 ? Double(samples.count) / Double(sampleRate) : 0
    }

    /// RIFF/WAVE encoding, accepted by every transcription API.
    public var wavData: Data {
        var data = Data()
        let byteRate = sampleRate * 2
        let dataSize = samples.count * 2

        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }

        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16))          // PCM chunk size
        append(UInt16(1))           // PCM format
        append(UInt16(1))           // mono
        append(UInt32(sampleRate))
        append(UInt32(byteRate))
        append(UInt16(2))           // block align
        append(UInt16(16))          // bits per sample
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(dataSize))
        samples.withUnsafeBufferPointer { buffer in
            for sample in buffer { append(sample) }
        }
        return data
    }

    /// Parses 16-bit PCM WAV data (mono or stereo, any rate). Used by the
    /// pipeline CLI and tests.
    public init?(wav data: Data) {
        guard data.count > 44,
              String(data: data[0..<4], encoding: .ascii) == "RIFF",
              String(data: data[8..<12], encoding: .ascii) == "WAVE" else { return nil }

        func u16(_ offset: Int) -> UInt16 {
            UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
        }
        func u32(_ offset: Int) -> UInt32 {
            UInt32(u16(offset)) | UInt32(u16(offset + 2)) << 16
        }

        var offset = 12
        var channels = 1
        var rate = 16_000
        var bits = 16
        while offset + 8 <= data.count {
            let id = String(data: data[offset..<offset + 4], encoding: .ascii) ?? ""
            let size = Int(u32(offset + 4))
            let body = offset + 8
            if id == "fmt " {
                channels = Int(u16(body + 2))
                rate = Int(u32(body + 4))
                bits = Int(u16(body + 14))
            } else if id == "data" {
                guard bits == 16, channels >= 1 else { return nil }
                let end = min(body + size, data.count)
                var out: [Int16] = []
                out.reserveCapacity((end - body) / 2 / channels)
                var i = body
                while i + 2 * channels <= end {
                    out.append(Int16(bitPattern: u16(i)))
                    i += 2 * channels
                }
                self.init(samples: out, sampleRate: rate)
                return
            }
            offset = body + size + (size % 2)
        }
        return nil
    }
}

public enum AudioLevel {
    /// Root-mean-square level of float samples in [-1, 1], as 0...1 on a
    /// perceptual (dB) scale suitable for a meter.
    public static func meterLevel(rms: Float) -> Float {
        let db = 20 * log10(max(rms, 1e-7))
        // -55 dB (quiet room) → 0, -10 dB (loud speech) → 1.
        return min(1, max(0, (db + 55) / 45))
    }

    public static func rms(_ samples: UnsafeBufferPointer<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        return (sum / Float(samples.count)).squareRoot()
    }

    /// Seconds of the clip that contain speech-level energy, measured in 30 ms
    /// frames. Used to skip transcription of silence (which is also when
    /// recognizers hallucinate).
    public static func voicedSeconds(_ clip: AudioClip, thresholdDBFS: Float = -42) -> Double {
        let frame = max(1, clip.sampleRate * 30 / 1000)
        let threshold = powf(10, thresholdDBFS / 20) * Float(Int16.max)
        var voicedFrames = 0
        var index = 0
        let samples = clip.samples
        while index < samples.count {
            let end = min(index + frame, samples.count)
            var sum: Float = 0
            for i in index..<end {
                let s = Float(samples[i])
                sum += s * s
            }
            let rms = (sum / Float(end - index)).squareRoot()
            if rms > threshold { voicedFrames += 1 }
            index = end
        }
        return Double(voicedFrames * frame) / Double(clip.sampleRate)
    }
}
