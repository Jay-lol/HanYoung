// HanYoung: Caps Lock 한영 전환 메뉴바 앱.
// 1) Caps Lock을 F19로 매핑  2) "이전 입력 소스 선택" 단축키를 fn+F19로  3) F19 누르는 즉시 전환 신호 발생
// 길게 누르면(0.5초) 영문으로 돌아가 Caps Lock을 토글한다.
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let switcher = Switcher()
    private var menu: StatusMenu!

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu = StatusMenu(switcher: switcher) { [weak self] in self?.toggleEnabled() }
        SystemInputMenu.hide()
        KeyMapping.setSwitchShortcut()
        KeyMapping.apply(true)
        InputSource.observeChanges { [weak self] in
            self?.switcher.inputSourceChanged()
            self?.menu.refresh()
        }
        // 새로 연결한 키보드나 재연결로 매핑이 풀린 키보드에 다시 건다. 권한이 나중에 허용되면 그때 키 감시를 시작한다.
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self, self.switcher.enabled else { return }
            KeyMapping.apply(true)
            if !self.switcher.isRunning && self.switcher.start() { self.menu.refresh() }
        }
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        switcher.start()
        menu.refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        KeyMapping.apply(false)
        KeyMapping.restoreSwitchShortcut()
        SystemInputMenu.restore()
    }

    private func toggleEnabled() {
        switcher.enabled.toggle()
        KeyMapping.apply(switcher.enabled)
        if switcher.enabled { KeyMapping.setSwitchShortcut() } else { KeyMapping.restoreSwitchShortcut() }
        menu.refresh()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
