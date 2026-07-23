#!/usr/bin/env swift

import AppKit
import Darwin

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write(Data("缺少背景图输出路径\n".utf8))
    exit(1)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let appIconURL = CommandLine.arguments.count >= 3
    ? URL(fileURLWithPath: CommandLine.arguments[2])
    : nil
let canvasSize = CGSize(width: 720, height: 440)
let scale: CGFloat = 2

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize.width * scale),
    pixelsHigh: Int(canvasSize.height * scale),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    FileHandle.standardError.write(Data("无法创建 DMG 背景画布\n".utf8))
    exit(1)
}
bitmap.size = canvasSize

guard let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
    FileHandle.standardError.write(Data("无法创建 DMG 背景绘图上下文\n".utf8))
    exit(1)
}

func rectFromTop(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
    CGRect(x: x, y: canvasSize.height - y - height, width: width, height: height)
}

func drawText(
    _ text: String,
    topX: CGFloat,
    topY: CGFloat,
    width: CGFloat,
    height: CGFloat,
    font: NSFont,
    color: NSColor,
    alignment: NSTextAlignment = .left
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byTruncatingTail
    let value = NSAttributedString(
        string: text,
        attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
    )
    value.draw(in: rectFromTop(x: topX, y: topY, width: width, height: height))
}

func drawRoundedRect(
    _ rect: CGRect,
    radius: CGFloat,
    fill: NSColor,
    stroke: NSColor? = nil,
    lineWidth: CGFloat = 1
) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    fill.setFill()
    path.fill()
    if let stroke {
        stroke.setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics

let background = NSGradient(colors: [
    NSColor(srgbRed: 0.965, green: 0.985, blue: 0.975, alpha: 1),
    NSColor(srgbRed: 0.925, green: 0.965, blue: 0.945, alpha: 1)
])
background?.draw(in: CGRect(origin: .zero, size: canvasSize), angle: -90)

let glow = NSBezierPath(ovalIn: rectFromTop(x: 500, y: -120, width: 330, height: 330))
NSColor(srgbRed: 0.08, green: 0.78, blue: 0.42, alpha: 0.08).setFill()
glow.fill()

if let appIconURL, let icon = NSImage(contentsOf: appIconURL) {
    icon.draw(
        in: rectFromTop(x: 24, y: 24, width: 38, height: 38),
        from: .zero,
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: false,
        hints: [.interpolation: NSImageInterpolation.high]
    )
}

drawText(
    "安装轻截",
    topX: 76,
    topY: 23,
    width: 300,
    height: 28,
    font: .systemFont(ofSize: 21, weight: .bold),
    color: NSColor(srgbRed: 0.08, green: 0.18, blue: 0.12, alpha: 1)
)
drawText(
    "将左侧应用拖到右侧 Applications 文件夹",
    topX: 76,
    topY: 53,
    width: 440,
    height: 22,
    font: .systemFont(ofSize: 13, weight: .medium),
    color: NSColor(srgbRed: 0.32, green: 0.42, blue: 0.36, alpha: 1)
)

let divider = NSBezierPath()
divider.move(to: CGPoint(x: 24, y: canvasSize.height - 91))
divider.line(to: CGPoint(x: canvasSize.width - 24, y: canvasSize.height - 91))
NSColor.black.withAlphaComponent(0.08).setStroke()
divider.lineWidth = 1
divider.stroke()

let leftTarget = rectFromTop(x: 103, y: 126, width: 174, height: 176)
let rightTarget = rectFromTop(x: 443, y: 126, width: 174, height: 176)
drawRoundedRect(
    leftTarget,
    radius: 28,
    fill: NSColor.white.withAlphaComponent(0.68),
    stroke: NSColor.systemGreen.withAlphaComponent(0.30),
    lineWidth: 1.5
)
drawRoundedRect(
    rightTarget,
    radius: 28,
    fill: NSColor.white.withAlphaComponent(0.68),
    stroke: NSColor.systemGreen.withAlphaComponent(0.30),
    lineWidth: 1.5
)

func drawStepBadge(number: String, x: CGFloat) {
    let badgeRect = rectFromTop(x: x, y: 138, width: 27, height: 27)
    drawRoundedRect(
        badgeRect,
        radius: 13.5,
        fill: NSColor(srgbRed: 0.08, green: 0.76, blue: 0.39, alpha: 1)
    )
    drawText(
        number,
        topX: x,
        topY: 141,
        width: 27,
        height: 20,
        font: .systemFont(ofSize: 13, weight: .bold),
        color: .white,
        alignment: .center
    )
}

drawStepBadge(number: "1", x: 115)
drawStepBadge(number: "2", x: 455)

let arrowY = canvasSize.height - 218
let arrow = NSBezierPath()
arrow.move(to: CGPoint(x: 298, y: arrowY))
arrow.line(to: CGPoint(x: 419, y: arrowY))
arrow.lineCapStyle = .round
NSColor(srgbRed: 0.08, green: 0.76, blue: 0.39, alpha: 1).setStroke()
arrow.lineWidth = 7
arrow.stroke()

let arrowHead = NSBezierPath()
arrowHead.move(to: CGPoint(x: 409, y: arrowY + 14))
arrowHead.line(to: CGPoint(x: 427, y: arrowY))
arrowHead.line(to: CGPoint(x: 409, y: arrowY - 14))
arrowHead.lineCapStyle = .round
arrowHead.lineJoinStyle = .round
arrowHead.lineWidth = 7
arrowHead.stroke()

drawText(
    "拖到这里",
    topX: 300,
    topY: 177,
    width: 120,
    height: 22,
    font: .systemFont(ofSize: 12, weight: .semibold),
    color: NSColor(srgbRed: 0.08, green: 0.62, blue: 0.32, alpha: 1),
    alignment: .center
)

let tipRect = rectFromTop(x: 76, y: 355, width: 568, height: 56)
drawRoundedRect(
    tipRect,
    radius: 14,
    fill: NSColor.white.withAlphaComponent(0.66),
    stroke: NSColor.black.withAlphaComponent(0.06)
)
drawText(
    "安装完成后，从“应用程序”启动轻截",
    topX: 96,
    topY: 366,
    width: 360,
    height: 20,
    font: .systemFont(ofSize: 12.5, weight: .semibold),
    color: NSColor.black.withAlphaComponent(0.68)
)
drawText(
    "默认快捷键  ⌃⌘A",
    topX: 445,
    topY: 365,
    width: 178,
    height: 22,
    font: .monospacedSystemFont(ofSize: 13, weight: .bold),
    color: NSColor(srgbRed: 0.08, green: 0.66, blue: 0.34, alpha: 1),
    alignment: .right
)
drawText(
    "轻量、快速，在菜单栏常驻运行",
    topX: 96,
    topY: 386,
    width: 340,
    height: 18,
    font: .systemFont(ofSize: 11),
    color: NSColor.black.withAlphaComponent(0.42)
)

graphics.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("无法编码 DMG 背景图\n".utf8))
    exit(1)
}

do {
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try png.write(to: outputURL, options: .atomic)
} catch {
    FileHandle.standardError.write(Data("写入 DMG 背景图失败：\(error.localizedDescription)\n".utf8))
    exit(1)
}
