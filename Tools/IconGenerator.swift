// 앱 아이콘 생성기: 남색 배경 위에 메뉴바와 같은 KO(채움)/EN(테두리) 배지를 겹쳐 그린다.
// 사용법: swift Tools/IconGenerator.swift build/AppIcon.iconset && iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
import AppKit

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024  // 1024 기준 좌표

    // macOS 아이콘 그리드: 1024 캔버스 안 824 크기 둥근 사각형
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.shadowBlurRadius = 20 * s
    shadow.set()
    NSColor(red: 0.10, green: 0.17, blue: 0.40, alpha: 1).setFill()
    bodyPath.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(red: 0.20, green: 0.42, blue: 0.85, alpha: 1),
               ending: NSColor(red: 0.07, green: 0.13, blue: 0.36, alpha: 1))!.draw(in: bodyPath, angle: -90)

    func badge(_ label: String, center: NSPoint, filled: Bool) {
        let rect = NSRect(x: center.x - 230 * s, y: center.y - 150 * s, width: 460 * s, height: 300 * s)
        let path = NSBezierPath(roundedRect: rect, xRadius: 56 * s, yRadius: 56 * s)
        let font = NSFont.systemFont(ofSize: 170 * s, weight: .bold)
        let navy = NSColor(red: 0.12, green: 0.24, blue: 0.58, alpha: 1)
        let text = NSAttributedString(string: label, attributes: [.font: font, .kern: 6 * s,
                                                                 .foregroundColor: filled ? navy : NSColor.white])
        let textSize = text.size()
        let origin = NSPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2 + 4 * s)
        if filled {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
            shadow.shadowOffset = NSSize(width: 0, height: -12 * s)
            shadow.shadowBlurRadius = 28 * s
            shadow.set()
            NSColor.white.setFill()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()
        } else {
            NSColor.white.withAlphaComponent(0.9).setStroke()
            path.lineWidth = 22 * s
            path.stroke()
        }
        text.draw(at: origin)
    }
    // 뒤: EN(테두리), 앞: KO(채움)
    badge("EN", center: NSPoint(x: 600 * s, y: 395 * s), filled: false)
    badge("KO", center: NSPoint(x: 424 * s, y: 630 * s), filled: true)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try drawIcon(size: CGFloat(points * scale)).representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
}
