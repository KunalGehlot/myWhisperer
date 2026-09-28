import Foundation
@testable import MyWhispererCore

/// One second of speech-level sine tone (16 kHz). Built with a plain loop:
/// the equivalent one-line `map` is too slow for some compilers to type-check.
func makeTone(seconds: Double = 1, amplitude: Double = 8_000) -> AudioClip {
    let count = Int(16_000 * seconds)
    var samples: [Int16] = []
    samples.reserveCapacity(count)
    for index in 0..<count {
        let phase = Double(index) * 0.2
        let value: Double = amplitude * sin(phase)
        samples.append(Int16(value))
    }
    return AudioClip(samples: samples)
}
