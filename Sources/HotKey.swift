// HotKey.swift — 全局热键（Carbon RegisterEventHotKey，原版为 F9）
import AppKit
import Carbon.HIToolbox

final class GlobalHotKey {
    static let shared = GlobalHotKey()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    var onFire: (() -> Void)?

    private init() {}

    func registerCurrent() {
        unregister()
        installHandlerIfNeeded()

        let code = Prefs.hotKeyCode
        var keyCode: UInt32
        var mods: UInt32 = 0
        switch code {
        case -1: keyCode = UInt32(kVK_ANSI_P); mods = UInt32(optionKey | cmdKey)
        case -2: keyCode = UInt32(kVK_ANSI_P); mods = UInt32(controlKey | optionKey)
        default: keyCode = UInt32(code)
        }

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x504F_4658), id: 1) // 'POFX'
        let status = RegisterEventHotKey(keyCode, mods, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr { hotKeyRef = ref }
    }

    func unregister() {
        if let r = hotKeyRef { UnregisterEventHotKey(r); hotKeyRef = nil }
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData -> OSStatus in
            guard let userData else { return noErr }
            let me = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { me.onFire?() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }
}
