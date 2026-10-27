import AppKit
import Carbon

// The global ⌃⌘V shortcut that opens the shelf from any app.
enum HotKey {
    static func register() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { (NSApp.delegate as? AppDelegate)?.hotKeyPressed() }
            }
            return noErr
        }, 1, &spec, nil, nil)
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x4350_4354), id: 1)   // 'CPCT'
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(cmdKey | controlKey), id,
                                         GetApplicationEventTarget(), 0, &ref)
        if status != noErr {
            NSLog("Copycat: couldn't register ⌃⌘V (error %d); another app may be using it", status)
        }
    }
}
