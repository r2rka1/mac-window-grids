import Carbon.HIToolbox
import Foundation

/// Global ⌃⌥1 … ⌃⌥9 hotkeys. Carbon hotkeys need no permission.
final class HotKeys {
    var onKey: ((Int) -> Void)?
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    private static let digitKeyCodes = [
        kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7,
        kVK_ANSI_8, kVK_ANSI_9,
    ]

    func setEnabled(_ on: Bool) {
        on ? register() : unregister()
    }

    private func register() {
        guard refs.isEmpty else { return }
        if handler == nil {
            var spec = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(
                GetApplicationEventTarget(),
                { _, event, userData in
                    var id = EventHotKeyID()
                    GetEventParameter(
                        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                        nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                    if let userData {
                        let me = Unmanaged<HotKeys>.fromOpaque(userData).takeUnretainedValue()
                        let n = Int(id.id)
                        DispatchQueue.main.async { me.onKey?(n) }
                    }
                    return noErr
                }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        }
        for (i, code) in Self.digitKeyCodes.enumerated() {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x5747_5244), id: UInt32(i + 1))  // 'WGRD'
            let status = RegisterEventHotKey(
                UInt32(code), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { refs.append(ref) }
        }
    }

    private func unregister() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
    }
}
