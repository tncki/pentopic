// HotKey.swift — 全局热键：任意组合键录制 + 注册
//
// 原版 Pointofix 固定用 F9。这里做成可自定义：用户按下什么组合就用什么，
// 和 macOS 应用的通行做法一致。
//
// 两个关键设计：
//  1. **必须带修饰键，或者是功能键**。否则一个裸字母（比如 P）会被全局劫持，
//     用户在任何程序里都打不出那个字。
//  2. 会话进行中会**临时注销全局热键**，改由应用内的键盘事件处理。
//     否则热键会系统级吞掉按键（比如把 ⌘P 设成热键后就没法打印了）。
import AppKit
import SwiftUI
import Carbon.HIToolbox

// MARK: - 快捷键描述

struct HotKeySpec: Equatable {
    /// 虚拟键码（Carbon/AppKit 通用）
    var keyCode: UInt32
    /// Carbon 修饰键掩码（cmdKey / optionKey / controlKey / shiftKey）
    var modifiers: UInt32

    static let `default` = HotKeySpec(keyCode: UInt32(kVK_F9), modifiers: 0)

    // MARK: 合法性

    /// 功能键不需要修饰键
    static func isFunctionKey(_ code: UInt32) -> Bool {
        let codes: Set<UInt32> = [
            UInt32(kVK_F1), UInt32(kVK_F2), UInt32(kVK_F3), UInt32(kVK_F4),
            UInt32(kVK_F5), UInt32(kVK_F6), UInt32(kVK_F7), UInt32(kVK_F8),
            UInt32(kVK_F9), UInt32(kVK_F10), UInt32(kVK_F11), UInt32(kVK_F12),
            UInt32(kVK_F13), UInt32(kVK_F14), UInt32(kVK_F15), UInt32(kVK_F16),
            UInt32(kVK_F17), UInt32(kVK_F18), UInt32(kVK_F19), UInt32(kVK_F20),
            UInt32(kVK_Help), UInt32(kVK_ForwardDelete), UInt32(kVK_Home),
            UInt32(kVK_End), UInt32(kVK_PageUp), UInt32(kVK_PageDown)
        ]
        return codes.contains(code)
    }

    var isValid: Bool { modifiers != 0 || HotKeySpec.isFunctionKey(keyCode) }

    // MARK: 与事件比对

    func matches(_ event: NSEvent) -> Bool {
        UInt32(event.keyCode) == keyCode && HotKeySpec.carbonModifiers(event.modifierFlags) == modifiers
    }

    static func carbonModifiers(_ f: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if f.contains(.command) { m |= UInt32(cmdKey) }
        if f.contains(.option)  { m |= UInt32(optionKey) }
        if f.contains(.control) { m |= UInt32(controlKey) }
        if f.contains(.shift)   { m |= UInt32(shiftKey) }
        return m
    }

    // MARK: 显示

    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        return s + HotKeySpec.keyName(keyCode)
    }

    /// 键码 → 可读名称。功能键查表，其余走当前键盘布局（德语键盘的 Z/Y 也是对的）。
    static func keyName(_ keyCode: UInt32) -> String {
        let special: [UInt32: String] = [
            UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
            UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
            UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
            UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
            UInt32(kVK_F13): "F13", UInt32(kVK_F14): "F14", UInt32(kVK_F15): "F15",
            UInt32(kVK_F16): "F16", UInt32(kVK_F17): "F17", UInt32(kVK_F18): "F18",
            UInt32(kVK_F19): "F19", UInt32(kVK_F20): "F20",
            UInt32(kVK_Space): "Space", UInt32(kVK_Return): "↩", UInt32(kVK_Tab): "⇥",
            UInt32(kVK_Escape): "⎋", UInt32(kVK_Delete): "⌫",
            UInt32(kVK_ForwardDelete): "⌦",
            UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→",
            UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓",
            UInt32(kVK_Home): "↖", UInt32(kVK_End): "↘",
            UInt32(kVK_PageUp): "⇞", UInt32(kVK_PageDown): "⇟"
        ]
        if let s = special[keyCode] { return s }

        // 普通按键：用当前键盘布局翻译
        guard let src = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else {
            return "Key\(keyCode)"
        }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        var dead: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 8)
        var length = 0
        let status = data.withUnsafeBytes { buf -> OSStatus in
            guard let layout = buf.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                                  UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                  &dead, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "Key\(keyCode)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }

    // MARK: 与系统快捷键的冲突提示（返回 nil 表示无已知冲突）

    var conflictWarning: String? {
        guard modifiers == UInt32(cmdKey) else { return nil }
        switch Int(keyCode) {
        case kVK_ANSI_P:
            return LS("⚠️ ⌘P ist systemweit „Drucken“ – andere Programme können dann nicht mehr drucken. Zum Drucken den Knopf in der Werkzeugleiste verwenden.",
                      "⚠️ ⌘P is the system-wide Print shortcut — other apps will no longer be able to print. Use the toolbar button to print instead.",
                      "⚠️ ⌘P 是系统级的「打印」快捷键 —— 设成热键后其他所有程序的打印都会失效。需要打印时请用工具栏上的按钮。",
                      "⚠️ ⌘P 是系統級的「列印」快速鍵 —— 設成熱鍵後其他所有程式的列印都會失效。需要列印時請用工具列上的按鈕。")
        case kVK_ANSI_C:
            return LS("⚠️ ⌘C ist systemweit „Kopieren“ – in anderen Programmen funktioniert Kopieren dann nicht mehr.",
                      "⚠️ ⌘C is the system-wide Copy shortcut — copying in other apps will stop working.",
                      "⚠️ ⌘C 是系统级的「复制」快捷键 —— 其他程序的复制会失效。",
                      "⚠️ ⌘C 是系統級的「複製」快速鍵 —— 其他程式的複製會失效。")
        case kVK_ANSI_V:
            return LS("⚠️ ⌘V ist systemweit „Einsetzen“ – in anderen Programmen funktioniert Einsetzen dann nicht mehr.",
                      "⚠️ ⌘V is the system-wide Paste shortcut — pasting in other apps will stop working.",
                      "⚠️ ⌘V 是系统级的「粘贴」快捷键 —— 其他程序的粘贴会失效。",
                      "⚠️ ⌘V 是系統級的「貼上」快速鍵 —— 其他程式的貼上會失效。")
        case kVK_ANSI_X:
            return LS("⚠️ ⌘X ist systemweit „Ausschneiden“.",
                      "⚠️ ⌘X is the system-wide Cut shortcut.",
                      "⚠️ ⌘X 是系统级的「剪切」快捷键。",
                      "⚠️ ⌘X 是系統級的「剪下」快速鍵。")
        case kVK_ANSI_S:
            return LS("⚠️ ⌘S ist systemweit „Speichern“.",
                      "⚠️ ⌘S is the system-wide Save shortcut.",
                      "⚠️ ⌘S 是系统级的「保存」快捷键。",
                      "⚠️ ⌘S 是系統級的「儲存」快速鍵。")
        case kVK_ANSI_Q:
            return LS("⚠️ ⌘Q ist systemweit „Programm beenden“ – andere Programme lassen sich dann nicht mehr damit beenden.",
                      "⚠️ ⌘Q is the system-wide Quit shortcut — other apps can no longer be quit with it.",
                      "⚠️ ⌘Q 是系统级的「退出程序」快捷键 —— 其他程序将无法用它退出。",
                      "⚠️ ⌘Q 是系統級的「結束程式」快速鍵 —— 其他程式將無法用它結束。")
        case kVK_ANSI_W:
            return LS("⚠️ ⌘W ist systemweit „Fenster schließen“.",
                      "⚠️ ⌘W is the system-wide Close Window shortcut.",
                      "⚠️ ⌘W 是系统级的「关闭窗口」快捷键。",
                      "⚠️ ⌘W 是系統級的「關閉視窗」快速鍵。")
        case kVK_ANSI_A:
            return LS("⚠️ ⌘A ist systemweit „Alles auswählen“.",
                      "⚠️ ⌘A is the system-wide Select All shortcut.",
                      "⚠️ ⌘A 是系统级的「全选」快捷键。",
                      "⚠️ ⌘A 是系統級的「全選」快速鍵。")
        case kVK_ANSI_Z:
            return LS("⚠️ ⌘Z ist systemweit „Rückgängig“.",
                      "⚠️ ⌘Z is the system-wide Undo shortcut.",
                      "⚠️ ⌘Z 是系统级的「撤销」快捷键。",
                      "⚠️ ⌘Z 是系統級的「復原」快速鍵。")
        default:
            return nil
        }
    }
}

// MARK: - 录制控件

/// 点一下，然后按下想要的组合键 —— 与 macOS 各应用的快捷键设置一致。
final class HotKeyRecorderView: NSView {
    var spec: HotKeySpec = .default { didSet { needsDisplay = true } }
    var onChange: ((HotKeySpec) -> Void)?
    var onRejected: ((String) -> Void)?

    private var recording = false
    private var monitor: Any?

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
        (recording ? NSColor.controlAccentColor.withAlphaComponent(0.18)
                   : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = recording ? 2 : 1
        path.stroke()

        let text = recording
            ? LS("Tastenkombination drücken …", "Press a key combination …",
                 "请按下组合键 …", "請按下組合鍵 …")
            : spec.display
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: recording ? .regular : .semibold),
            .foregroundColor: recording ? NSColor.secondaryLabelColor : NSColor.labelColor
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                                            y: (bounds.height - size.height) / 2),
                                withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        startRecording()
    }

    private func startRecording() {
        recording = true
        needsDisplay = true
        // 用本地事件监视器而不是 keyDown：功能键、带修饰键的组合都能拿到，
        // 而且可以把事件整段吞掉，避免录制过程中触发别的快捷键。
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] e in
            guard let self, self.recording else { return e }
            self.handle(e)
            return nil
        }
    }

    private func stopRecording() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        needsDisplay = true
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) { stopRecording(); return }
        let newSpec = HotKeySpec(keyCode: UInt32(event.keyCode),
                                 modifiers: HotKeySpec.carbonModifiers(event.modifierFlags))
        guard newSpec.isValid else {
            onRejected?(LS("Bitte mit ⌘ ⌥ ⌃ ⇧ kombinieren oder eine Funktionstaste (F1–F20) verwenden.",
                           "Combine it with ⌘ ⌥ ⌃ ⇧, or use a function key (F1–F20).",
                           "请搭配 ⌘ ⌥ ⌃ ⇧ 使用，或改用功能键（F1–F20）。",
                           "請搭配 ⌘ ⌥ ⌃ ⇧ 使用，或改用功能鍵（F1–F20）。"))
            return
        }
        spec = newSpec          // 注意别用局部变量遮蔽属性，否则这里会变成空操作
        stopRecording()
        onChange?(newSpec)
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return true
    }

    deinit { if let m = monitor { NSEvent.removeMonitor(m) } }
}

// MARK: - SwiftUI 封装

struct HotKeyRecorder: NSViewRepresentable {
    @Binding var spec: HotKeySpec
    var onWarning: (String?) -> Void

    func makeNSView(context: Context) -> HotKeyRecorderView {
        let v = HotKeyRecorderView()
        v.spec = spec
        v.onChange = { s in
            DispatchQueue.main.async {
                spec = s
                onWarning(s.conflictWarning)
            }
        }
        v.onRejected = { msg in DispatchQueue.main.async { onWarning(msg) } }
        return v
    }

    func updateNSView(_ v: HotKeyRecorderView, context: Context) {
        if v.spec != spec { v.spec = spec }
    }
}

// MARK: - 全局热键注册

final class GlobalHotKey {
    static let shared = GlobalHotKey()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    var onFire: (() -> Void)?
    private(set) var isRegistered = false

    private init() {}

    func registerCurrent() { register(Prefs.hotKeySpec) }

    func register(_ spec: HotKeySpec) {
        unregister()
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x504F_4658), id: 1) // 'POFX'
        let status = RegisterEventHotKey(spec.keyCode, spec.modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr { hotKeyRef = ref; isRegistered = true }
    }

    func unregister() {
        if let r = hotKeyRef { UnregisterEventHotKey(r); hotKeyRef = nil }
        isRegistered = false
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
