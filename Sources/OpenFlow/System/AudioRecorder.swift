import AVFoundation
import CoreAudio
import OpenFlowCore

struct AudioInputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let isBluetooth: Bool
}

enum AudioDevices {
    static func inputDevices() -> [AudioInputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            guard inputChannelCount(id) > 0,
                  let uid = stringProperty(id, kAudioDevicePropertyDeviceUID),
                  let name = stringProperty(id, kAudioObjectPropertyName) else { return nil }
            let transport = uint32Property(id, kAudioDevicePropertyTransportType)
            let bluetooth = transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
            return AudioInputDevice(id: id, uid: uid, name: name, isBluetooth: bluetooth)
        }
    }

    static func defaultInputDevice() -> AudioInputDevice? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr else { return nil }
        return inputDevices().first { $0.id == id }
    }

    private static func inputChannelCount(_ id: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func stringProperty(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func uint32Property(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> UInt32 {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
        return value
    }
}

/// Captures the microphone as 16 kHz mono PCM and reports a live level.
final class AudioRecorder: AudioSource {
    /// Called on the main thread ~20 times a second with a 0...1 level.
    var onLevel: ((Float) -> Void)?
    /// CoreAudio device UID to record from; nil = system default.
    var deviceUID: String?

    private var engine: AVAudioEngine?
    private let buffer = SampleBuffer()
    private var monitoring = false

    enum RecorderError: Error {
        case noInput
    }

    func start() throws {
        try startEngine(storeSamples: true)
    }

    /// Level metering only (mic test in onboarding/settings).
    func startMonitoring() throws {
        guard engine == nil else { return }
        monitoring = true
        try startEngine(storeSamples: false)
    }

    func stopMonitoring() {
        guard monitoring else { return }
        monitoring = false
        teardown()
    }

    func stop() -> AudioClip {
        teardown()
        return AudioClip(samples: buffer.drain(), sampleRate: 16_000)
    }

    func cancel() {
        teardown()
        _ = buffer.drain()
    }

    private func startEngine(storeSamples: Bool) throws {
        teardown()
        _ = buffer.drain()
        monitoring = !storeSamples

        let engine = AVAudioEngine()
        let input = engine.inputNode
        if let deviceUID, let device = AudioDevices.inputDevices().first(where: { $0.uid == deviceUID }),
           let unit = input.audioUnit {
            var id = device.id
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                 &id, UInt32(MemoryLayout<AudioDeviceID>.size))
        }

        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
              let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw RecorderError.noInput
        }

        let store = buffer
        // Logged once per recording: how long until the first audio arrives
        // (Bluetooth mics can take several hundred ms and clip first words).
        let startedAt = Date()
        let firstBuffer = OnceFlag()
        let levelMeter = LevelThrottle { [weak self] level in
            DispatchQueue.main.async { self?.onLevel?(level) }
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { pcm, _ in
            if firstBuffer.claim() {
                NSLog("OpenFlow audio: first buffer after \(Int(Date().timeIntervalSince(startedAt) * 1000)) ms (\(Int(inputFormat.sampleRate)) Hz, \(inputFormat.channelCount) ch)")
            }
            if let channel = pcm.floatChannelData?[0] {
                let rms = AudioLevel.rms(UnsafeBufferPointer(start: channel, count: Int(pcm.frameLength)))
                levelMeter.report(AudioLevel.meterLevel(rms: rms))
            }
            guard storeSamples else { return }

            let ratio = outputFormat.sampleRate / inputFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(pcm.frameLength) * ratio) + 32
            guard let out = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }
            var consumed = false
            var error: NSError?
            converter.convert(to: out, error: &error) { _, status in
                if consumed {
                    status.pointee = .noDataNow
                    return nil
                }
                consumed = true
                status.pointee = .haveData
                return pcm
            }
            if error == nil, let data = out.int16ChannelData?[0] {
                store.append(UnsafeBufferPointer(start: data, count: Int(out.frameLength)))
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        self.engine = engine
    }

    private func teardown() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        DispatchQueue.main.async { [weak self] in self?.onLevel?(0) }
    }
}

/// Thread-safe sample accumulator written from the audio thread.
private final class SampleBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Int16] = []

    func append(_ chunk: UnsafeBufferPointer<Int16>) {
        lock.lock()
        samples.append(contentsOf: chunk)
        lock.unlock()
    }

    func drain() -> [Int16] {
        lock.lock()
        defer { lock.unlock() }
        let out = samples
        samples = []
        samples.reserveCapacity(16_000 * 30)
        return out
    }
}

private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

/// Emits at most ~20 levels per second, smoothing peaks.
private final class LevelThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var last = Date.distantPast
    private var peak: Float = 0
    private let emit: (Float) -> Void

    init(emit: @escaping (Float) -> Void) { self.emit = emit }

    func report(_ level: Float) {
        lock.lock()
        peak = max(peak, level)
        let now = Date()
        guard now.timeIntervalSince(last) >= 0.05 else {
            lock.unlock()
            return
        }
        let value = peak
        peak = 0
        last = now
        lock.unlock()
        emit(value)
    }
}
