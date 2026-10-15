// Caps Lock을 F19로 바꾸는 HID 매핑과, F19를 "이전 입력 소스 선택"에 거는 시스템 단축키.
import AppKit

let capsLockUsage: UInt64 = 0x700000039
let f19Usage: UInt64 = 0x70000006e
let f19KeyCode: Int64 = 80

private let srcKey = "HIDKeyboardModifierMappingSrc", dstKey = "HIDKeyboardModifierMappingDst"
private typealias Mapping = [String: NSNumber]

enum KeyMapping {
    // 모든 키보드에 Caps Lock → F19를 걸거나 우리 매핑만 뺀다. 다른 매핑은 그대로 둔다.
    static func apply(_ enabled: Bool) {
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        let services = (IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] ?? [])
            .filter { IOHIDServiceClientConformsTo($0, 1, 6) != 0 }
        let ours: Mapping = [srcKey: NSNumber(value: capsLockUsage), dstKey: NSNumber(value: f19Usage)]
        for service in services {
            let current = IOHIDServiceClientCopyProperty(service, "UserKeyMapping" as CFString) as? [Mapping] ?? []
            var next = enabled ? current.filter { $0[srcKey]?.uint64Value != capsLockUsage } : current.filter { $0 != ours }
            if enabled { next.append(ours) }
            if next != current { IOHIDServiceClientSetProperty(service, "UserKeyMapping" as CFString, next as CFArray) }
        }
    }

    // 시스템 설정 > 키보드 단축키 > 입력 소스 > "이전 입력 소스 선택"(ID 60)을 fn+F19로. 원래 값을 저장해두고, 종료·비활성화 시 되돌린다.
    // F19 이벤트에는 fn 플래그가 붙어 와서, 수식키 없이 등록하면 영어→한글 전환이 먹지 않는다.
    private static let wantedShortcut: NSDictionary = ["enabled": true, "value": ["type": "standard", "parameters": [65535, Int(f19KeyCode), Int(CGEventFlags.maskSecondaryFn.rawValue)]]]

    static func setSwitchShortcut() {
        let defaults = UserDefaults.standard
        let current = switchShortcut
        if !defaults.bool(forKey: "shortcutBackedUp") {
            // 이미 fn+F19면(예전 버전이 덮어쓴 채 남은 경우) 원래 값을 알 수 없으니 macOS 기본값(Control+Space)으로 되돌리게 비워둔다.
            defaults.set(current?.isEqual(to: wantedShortcut) == true ? nil : current, forKey: "originalShortcut")
            defaults.set(true, forKey: "shortcutBackedUp")
        }
        if current?.isEqual(to: wantedShortcut) != true { switchShortcut = wantedShortcut }
    }

    static func restoreSwitchShortcut() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "shortcutBackedUp") else { return }
        switchShortcut = defaults.dictionary(forKey: "originalShortcut") as NSDictionary?  // nil이면 항목을 지워 macOS 기본값으로
        defaults.removeObject(forKey: "originalShortcut")
        defaults.removeObject(forKey: "shortcutBackedUp")
    }

    private static var switchShortcut: NSDictionary? {
        get {
            CFPreferencesAppSynchronize(hotKeysDomain)
            return (CFPreferencesCopyAppValue(hotKeysKey, hotKeysDomain) as? [String: Any])?["60"] as? NSDictionary
        }
        set {
            var keys = CFPreferencesCopyAppValue(hotKeysKey, hotKeysDomain) as? [String: Any] ?? [:]
            keys["60"] = newValue
            CFPreferencesSetAppValue(hotKeysKey, keys as CFDictionary, hotKeysDomain)
            CFPreferencesAppSynchronize(hotKeysDomain)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings")
            process.arguments = ["-u", "-virtualSession"]
            try? process.run(); process.waitUntilExit()
        }
    }

    private static let hotKeysDomain = "com.apple.symbolichotkeys" as CFString, hotKeysKey = "AppleSymbolicHotKeys" as CFString
}
