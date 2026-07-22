import AppKit

@MainActor
final class ScrollCaptureHUDController {
    private let onFinish: () -> Void
    private let borderWindow: NSPanel
    private let controlWindow: NSPanel
    private let label = NSTextField(labelWithString: "向下滚动页面，完成后点击完成")

    init(selection: Selection, onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        borderWindow = NSPanel(
            contentRect: selection.globalRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        borderWindow.level = .screenSaver
        borderWindow.isOpaque = false
        borderWindow.backgroundColor = .clear
        borderWindow.ignoresMouseEvents = true
        borderWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        borderWindow.contentView?.wantsLayer = true
        borderWindow.contentView?.layer?.borderWidth = 2
        borderWindow.contentView?.layer?.borderColor = NSColor.systemGreen.cgColor

        controlWindow = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 300, height: 46),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        controlWindow.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        controlWindow.isOpaque = false
        controlWindow.backgroundColor = .clear
        controlWindow.hasShadow = true
        controlWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let finish = NSButton(title: "完成", target: nil, action: nil)
        let stack = NSStackView(views: [label, finish])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 7, left: 10, bottom: 7, right: 10)
        stack.wantsLayer = true
        stack.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor
        stack.layer?.cornerRadius = 8
        finish.target = self
        finish.action = #selector(finishCapture)
        controlWindow.contentView = stack

        let desiredX = min(selection.globalRect.maxX - 300, selection.screenFrame.maxX - 308)
        var desiredY = selection.globalRect.maxY + 8
        if desiredY + 46 > selection.screenFrame.maxY { desiredY = selection.globalRect.minY - 54 }
        controlWindow.setFrameOrigin(CGPoint(x: max(selection.screenFrame.minX + 8, desiredX), y: max(selection.screenFrame.minY + 8, desiredY)))
    }

    func show() {
        borderWindow.orderFrontRegardless()
        controlWindow.orderFrontRegardless()
    }

    func update(result: StitchAppendResult, totalHeight: Int) {
        switch result {
        case .noMatch:
            label.stringValue = "未识别到连续内容，请放慢滚动"
            label.textColor = .systemOrange
        case .limitReached:
            label.stringValue = "已达到长图上限，正在完成"
            label.textColor = .systemOrange
            onFinish()
        default:
            label.stringValue = "已捕获 \(totalHeight) px，继续向下滚动"
            label.textColor = .labelColor
        }
    }

    func close() {
        borderWindow.orderOut(nil)
        controlWindow.orderOut(nil)
    }

    @objc private func finishCapture() { onFinish() }
}
