import AppKit
import Carbon.HIToolbox

/// System-wide hotkeys via Carbon RegisterEventHotKey — works without any
/// permission prompts (unlike NSEvent global monitors).
///   ⌃⌥W toggle drawer · ⌃⌥S screenshot · ⌃⌥R record
final class HotKeys {
    static let shared = HotKeys()
    var onToggleDrawer: (() -> Void)?
    var onScreenshot: (() -> Void)?
    var onRecord: (() -> Void)?

    private var refs: [EventHotKeyRef?] = []

    func register() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            HotKeys.shared.handle(id: hotKeyID.id)
            return noErr
        }, 1, &eventType, nil, nil)

        registerKey(id: 1, keyCode: UInt32(kVK_ANSI_W))
        registerKey(id: 2, keyCode: UInt32(kVK_ANSI_S))
        registerKey(id: 3, keyCode: UInt32(kVK_ANSI_R))
    }

    private func registerKey(id: UInt32, keyCode: UInt32) {
        var ref: EventHotKeyRef?
        let modifiers = UInt32(controlKey | optionKey) // ⌃⌥
        RegisterEventHotKey(keyCode, modifiers,
                            EventHotKeyID(signature: 0x77616321 /* 'wac!' */, id: id),
                            GetApplicationEventTarget(), 0, &ref)
        refs.append(ref)
    }

    private func handle(id: UInt32) {
        DispatchQueue.main.async { [weak self] in
            switch id {
            case 1: self?.onToggleDrawer?()
            case 2: self?.onScreenshot?()
            case 3: self?.onRecord?()
            default: break
            }
        }
    }
}
