import AppKit
import OpenFlowCore

/// Short, soft synthesized cues so dictation feels responsive without
/// looking at the screen.
final class SoundPlayer {
    var volume: Float = 0.5
    private var sounds: [SoundCueKey: NSSound] = [:]

    private enum SoundCueKey: Hashable {
        case start, lock, stop, cancel, error
    }

    init() {
        sounds[.start] = Self.make([(660, 0.05), (990, 0.07)])
        sounds[.lock] = Self.make([(990, 0.045), (0, 0.03), (990, 0.045)])
        sounds[.stop] = Self.make([(880, 0.05), (587, 0.07)])
        sounds[.cancel] = Self.make([(440, 0.06), (330, 0.08)])
        sounds[.error] = Self.make([(311, 0.09), (0, 0.04), (233, 0.12)])
    }

    func play(_ cue: SoundCue) {
        let key: SoundCueKey = switch cue {
        case .start: .start
        case .lock: .lock
        case .stop: .stop
        case .cancel: .cancel
        case .error: .error
        }
        guard let sound = sounds[key] else { return }
        sound.stop()
        sound.volume = volume
        sound.play()
    }

    /// Renders a sequence of (frequency Hz, seconds) sine notes with soft
    /// attack/release envelopes into WAV data. Frequency 0 is a rest.
    private static func make(_ notes: [(Double, Double)]) -> NSSound? {
        let rate = 44_100.0
        var samples: [Int16] = []
        for (frequency, duration) in notes {
            let count = Int(rate * duration)
            for i in 0..<count {
                guard frequency > 0 else { samples.append(0); continue }
                let t = Double(i) / rate
                let attack = min(1, Double(i) / (rate * 0.008))
                let release = min(1, Double(count - i) / (rate * 0.03))
                // Fundamental plus a quiet octave for a rounder, bell-like tone.
                let wave = sin(2 * .pi * frequency * t) * 0.8 + sin(4 * .pi * frequency * t) * 0.2
                samples.append(Int16(wave * attack * release * 0.35 * Double(Int16.max)))
            }
        }
        return NSSound(data: AudioClip(samples: samples, sampleRate: Int(rate)).wavData)
    }
}
