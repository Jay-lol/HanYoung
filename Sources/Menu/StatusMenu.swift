// 메뉴바의 KO/EN 배지와 메뉴.
import AppKit
import ServiceManagement

// 한국어는 채운 배지, 영어는 테두리 배지.
private func badgeImage(_ label: String, filled: Bool) -> NSImage {
    let image = NSImage(size: NSSize(width: 22, height: 20), flipped: false) { rect in
        let shape = NSBezierPath(roundedRect: rect.insetBy(dx: 0.75, dy: 1.25), xRadius: 3, yRadius: 3)
        NSColor.black.set()
        if filled { shape.fill() } else { shape.lineWidth = 0.8; shape.stroke() }
        let text = NSAttributedString(string: label, attributes: [.font: NSFont.systemFont(ofSize: 9, weight: .semibold), .foregroundColor: NSColor.black])
        let size = text.size()
        let origin = NSPoint(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2)
        if filled {
            let mask = NSImage(size: rect.size, flipped: false) { _ in text.draw(at: origin); return true }
            mask.draw(in: rect, from: .zero, operation: .destinationOut, fraction: 1)
        } else { text.draw(at: origin) }
        return true
    }
    image.isTemplate = true
    return image
}

final class StatusMenu: NSObject, NSMenuDelegate {
    private let koreanBadge = badgeImage("KO", filled: true), englishBadge = badgeImage("EN", filled: false)
    private let item = NSStatusBar.system.statusItem(withLength: 28)
    private let switcher: Switcher
    private let onToggleEnabled: () -> Void

    init(switcher: Switcher, onToggleEnabled: @escaping () -> Void) {
        self.switcher = switcher
        self.onToggleEnabled = onToggleEnabled
        super.init()
        item.menu = NSMenu()
        item.menu?.delegate = self
        refresh()
    }

    // 현재 입력 소스 배지와, 키 감시가 꺼져 있으면 흐리게.
    func refresh() {
        let korean = InputSource.isKorean
        item.button?.image = korean ? koreanBadge : englishBadge
        item.button?.toolTip = "HanYoung · 현재 입력: \(korean ? "한국어" : "영어")"
        item.button?.appearsDisabled = !switcher.isRunning || !switcher.enabled
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.autoenablesItems = false
        let brand = menu.addItem(withTitle: "HanYoung", action: nil, keyEquivalent: "")
        brand.attributedTitle = NSAttributedString(string: "HanYoung", attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .heavy), .kern: 0.6])
        if !switcher.isRunning {
            menu.addItem(withTitle: "⚠️ 손쉬운 사용 권한 필요 — 허용하기…", action: #selector(openAccessibility), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        let korean = menu.addItem(withTitle: "한국어", action: #selector(selectKorean), keyEquivalent: "")
        korean.target = self; korean.image = koreanBadge; korean.state = InputSource.isKorean ? .on : .off
        let english = menu.addItem(withTitle: "영어", action: #selector(selectEnglish), keyEquivalent: "")
        english.target = self; english.image = englishBadge; english.state = InputSource.isEnglish ? .on : .off
        menu.addItem(.separator())
        let enabled = menu.addItem(withTitle: "활성화", action: #selector(toggleEnabled), keyEquivalent: "")
        enabled.target = self; enabled.state = switcher.enabled ? .on : .off
        let login = menu.addItem(withTitle: "로그인 시 시작", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self; login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func selectKorean() { InputSource.select(language: "ko") }
    @objc private func selectEnglish() { InputSource.select(language: "en") }
    @objc private func toggleEnabled() { onToggleEnabled() }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        try? service.status == .enabled ? service.unregister() : service.register()
    }

    @objc private func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}
