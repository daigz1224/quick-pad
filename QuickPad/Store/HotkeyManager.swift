import AppKit
import Carbon.HIToolbox

// `kVK_ANS_N` lives in `Carbon.HIToolbox.Events.h` but isn't always
// re-exported by the umbrella module on modern Xcodes. The value is
// stable ABI since 10.0 — see `HIToolbox/Events.h` — so we inline it.
private let kQuickPadKeyN: UInt32 = 0x2D

/// System-wide hotkey registration via Carbon's `RegisterEventHotKey`.
///
/// Why Carbon instead of `NSEvent.addGlobalMonitorForEvents`:
///   - `NSEvent` global monitors can only *observe* key events — they
///     cannot consume them. Another app would still receive the ⌥N,
///     which is unacceptable for a first-class capture hotkey.
///   - Carbon's hotkey API is old but still supported on modern macOS,
///     runs inside our own process, and crucially does **not** require
///     Accessibility permission (unlike CGEventTap).
///
/// `quick-capture` (⌥⇧N) is deliberately "always open, never close" so
/// a user hammering on it to capture something never accidentally
/// toggles the popover shut. The "toggle" (⌥N) variant keeps the
/// click-the-menu-bar-icon semantics.
final class HotkeyManager {

    enum Action: UInt32 {
        case togglePopover = 1
        case quickCapture  = 2
    }

    /// Called on the main queue when either registered hotkey fires.
    var onHotkey: ((Action) -> Void)?

    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var eventHandler: EventHandlerRef?

    // Arbitrary 4-char-code used to namespace our hotkey IDs. The value
    // doesn't matter as long as it's consistent across register/unregister.
    private let signature: OSType = {
        let chars: [UInt8] = Array("QPAD".utf8)
        return (OSType(chars[0]) << 24) | (OSType(chars[1]) << 16) | (OSType(chars[2]) << 8) | OSType(chars[3])
    }()

    func register() {
        installHandlerIfNeeded()
        registerHotkey(
            keyCode: kQuickPadKeyN,
            modifiers: UInt32(optionKey),
            action: .togglePopover
        )
        registerHotkey(
            keyCode: kQuickPadKeyN,
            modifiers: UInt32(optionKey | shiftKey),
            action: .quickCapture
        )
    }

    func unregister() {
        for ref in hotKeyRefs {
            if let ref { UnregisterEventHotKey(ref) }
        }
        hotKeyRefs.removeAll()
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }

    deinit {
        unregister()
    }

    // MARK: - Internals

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // Self pointer as userData so the C callback can find us again.
        // `passUnretained` is safe because `unregister` tears the
        // handler down before we're deallocated.
        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData, let event else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr, let action = Action(rawValue: hotKeyID.id) else {
                    return noErr
                }
                // Carbon delivers on the main thread already, but
                // `DispatchQueue.main.async` keeps the callback semantics
                // consistent and decouples the handler from whatever
                // AppKit state Carbon thinks we're in.
                DispatchQueue.main.async {
                    manager.onHotkey?(action)
                }
                return noErr
            },
            1,
            &eventSpec,
            selfPtr,
            &eventHandler
        )
    }

    private func registerHotkey(keyCode: UInt32, modifiers: UInt32, action: Action) {
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: signature, id: action.rawValue)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            hotKeyRefs.append(ref)
        } else {
            // Most common reason: the combo is already bound by another
            // process. We log and move on — the user can still click
            // the menu bar icon, and the other hotkey might still work.
            NSLog("QuickPad: failed to register hotkey (action=\(action), status=\(status)). Combo may be in use by another app.")
        }
    }
}
