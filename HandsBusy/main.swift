import CoreAudio
import Foundation

final class HandsBusy {
    static let shared = HandsBusy()

    private var preferredInputID: AudioDeviceID = 0
    private let queue = DispatchQueue(label: "eu.r3pr3ss10n.handsbusy")
    private var knownBTInputs: Set<AudioDeviceID> = []
    private var lastBTDeviceConnected: Date = .distantPast
    private let autoSwitchWindow: TimeInterval = 3
    private var inputAddr = AudioObjectPropertyAddress()
    private var devicesAddr = AudioObjectPropertyAddress()

    private init() {}

    func start() {
        queue.sync {
            preferredInputID = findPreferredInput()
            knownBTInputs = Set(inputDevices().filter { isBluetooth($0) })
            fixIfNeeded()
            installListeners()
        }
    }

    // MARK: - Device Queries

    private func allDevices() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr, size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices
        ) == noErr else { return [] }

        return devices
    }

    private func inputDevices() -> [AudioDeviceID] {
        allDevices().filter { hasInput($0) }
    }

    private func hasInput(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size)
        return size > 0
    }

    private func transportType(_ device: AudioDeviceID) -> UInt32 {
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport)
        return transport
    }

    private func isBluetooth(_ device: AudioDeviceID) -> Bool {
        let t = transportType(device)
        return t == kAudioDeviceTransportTypeBluetooth
            || t == kAudioDeviceTransportTypeBluetoothLE
    }

    private func defaultInput() -> AudioDeviceID {
        var device: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        return device
    }

    private func setDefaultInput(_ device: AudioDeviceID) {
        var dev = device
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, size, &dev
        )
    }

    // MARK: - Core Logic

    private func findPreferredInput() -> AudioDeviceID {
        let inputs = inputDevices().filter { !isBluetooth($0) }
        let usb = inputs.first { transportType($0) == kAudioDeviceTransportTypeUSB }
        let builtIn = inputs.first { transportType($0) == kAudioDeviceTransportTypeBuiltIn }
        return usb ?? builtIn ?? inputs.first ?? 0
    }

    private func fixIfNeeded() {
        let current = defaultInput()
        if isBluetooth(current) && preferredInputID != 0 {
            setDefaultInput(preferredInputID)
        }
    }

    // MARK: - CoreAudio Listeners

    private func installListeners() {
        let ptr = Unmanaged.passUnretained(self).toOpaque()

        inputAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &inputAddr,
            onDefaultInputChanged,
            ptr
        )

        devicesAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddr,
            onDevicesChanged,
            ptr
        )
    }

    func stop() {
        let ptr = Unmanaged.passUnretained(self).toOpaque()
        AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &inputAddr,
            onDefaultInputChanged,
            ptr
        )
        AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddr,
            onDevicesChanged,
            ptr
        )
    }

    fileprivate func handleInputChanged() {
        queue.async { [self] in
            let current = defaultInput()
            guard isBluetooth(current) else { return }

            let timeSinceConnect = Date().timeIntervalSince(lastBTDeviceConnected)
            guard timeSinceConnect < autoSwitchWindow else { return }

            preferredInputID = findPreferredInput()
            guard preferredInputID != 0 else { return }
            setDefaultInput(preferredInputID)
        }
    }

    fileprivate func handleDevicesChanged() {
        queue.async { [self] in
            let currentBTInputs = Set(inputDevices().filter { isBluetooth($0) })
            if !currentBTInputs.subtracting(knownBTInputs).isEmpty {
                lastBTDeviceConnected = Date()
            }
            knownBTInputs = currentBTInputs

            let newPreferred = findPreferredInput()
            if newPreferred != preferredInputID && newPreferred != 0 {
                preferredInputID = newPreferred
            }
        }
    }
}

// MARK: - C Callbacks

private func onDefaultInputChanged(
    _ objectID: AudioObjectID,
    _ count: UInt32,
    _ addresses: UnsafePointer<AudioObjectPropertyAddress>,
    _ ctx: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let ctx else { return noErr }
    Unmanaged<HandsBusy>.fromOpaque(ctx).takeUnretainedValue().handleInputChanged()
    return noErr
}

private func onDevicesChanged(
    _ objectID: AudioObjectID,
    _ count: UInt32,
    _ addresses: UnsafePointer<AudioObjectPropertyAddress>,
    _ ctx: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let ctx else { return noErr }
    Unmanaged<HandsBusy>.fromOpaque(ctx).takeUnretainedValue().handleDevicesChanged()
    return noErr
}

// MARK: - Entry

HandsBusy.shared.start()
RunLoop.main.run()
