// 현재 입력 소스 확인, 한국어/영어 직접 선택, macOS 기본 입력기 메뉴바 아이콘 숨김.
import AppKit
import Carbon

enum InputSource {
    static var currentLanguage: String { TISCopyCurrentKeyboardInputSource().map { language($0.takeRetainedValue()) } ?? "" }
    static var isEnglish: Bool { currentLanguage.hasPrefix("en") }
    static var isKorean: Bool { currentLanguage.hasPrefix("ko") }

    // 메뉴의 한국어/영어 선택. 단축키가 아니라 입력 소스를 직접 고른다.
    static func select(language prefix: String) {
        let filter = [kTISPropertyInputSourceIsEnabled as String: true, kTISPropertyInputSourceIsSelectCapable as String: true,
                      kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String] as CFDictionary
        let sources = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] ?? []
        if let source = sources.first(where: { language($0).hasPrefix(prefix) }) { TISSelectInputSource(source) }
    }

    // 입력 소스가 바뀔 때마다 handler를 메인 스레드에서 부른다.
    static func observeChanges(_ handler: @escaping () -> Void) {
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
                                                            object: nil, queue: .main) { _ in handler() }
    }

    private static func language(_ source: TISInputSource) -> String {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else { return "" }
        return (Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as? [String])?.first ?? ""
    }
}

// macOS 기본 입력기 메뉴바 아이콘(com.apple.TextInputMenu의 visible). 원래 값을 저장해두고 숨기며, 종료 시 되돌린다.
enum SystemInputMenu {
    private static let domain = "com.apple.TextInputMenu" as CFString

    static func hide() {
        let defaults = UserDefaults.standard
        CFPreferencesAppSynchronize(domain)
        let current = CFPreferencesCopyAppValue("visible" as CFString, domain)
        if !defaults.bool(forKey: "inputMenuBackedUp") {
            defaults.set(current, forKey: "originalInputMenu")
            defaults.set(true, forKey: "inputMenuBackedUp")
        }
        if (current as? NSNumber)?.boolValue != false { set(kCFBooleanFalse) }
    }

    static func restore() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "inputMenuBackedUp") else { return }
        set(defaults.object(forKey: "originalInputMenu") as CFPropertyList?)
        defaults.removeObject(forKey: "originalInputMenu")
        defaults.removeObject(forKey: "inputMenuBackedUp")
    }

    private static func set(_ value: CFPropertyList?) {
        CFPreferencesSetAppValue("visible" as CFString, value, domain)
        CFPreferencesAppSynchronize(domain)
        // launchd가 바로 다시 띄우는 에이전트라, 재시작해서 설정을 다시 읽게 한다.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["TextInputMenuAgent"]
        process.standardError = FileHandle.nullDevice
        try? process.run(); process.waitUntilExit()
    }
}
