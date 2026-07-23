import AppKit

@MainActor
final class ToolStyleViewController: NSViewController {
    private let tool: EditorTool
    private let onChange: (AnnotationStyle) -> Void
    private let onMosaicChange: (MosaicConfiguration) -> Void
    private var style: AnnotationStyle
    private var mosaicConfiguration: MosaicConfiguration
    private var colorButtons: [AnnotationColor: NSButton] = [:]
    private var widthButtons: [CGFloat: GlassToolbarButton] = [:]
    private var mosaicEffectButtons: [GlassToolbarButton] = []
    private var mosaicDrawingModeButtons: [GlassToolbarButton] = []

    init(
        tool: EditorTool,
        style: AnnotationStyle,
        mosaicConfiguration: MosaicConfiguration,
        onChange: @escaping (AnnotationStyle) -> Void,
        onMosaicChange: @escaping (MosaicConfiguration) -> Void
    ) {
        self.tool = tool
        self.style = style
        self.mosaicConfiguration = mosaicConfiguration
        self.onChange = onChange
        self.onMosaicChange = onMosaicChange
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let size = tool == .mosaic
            ? CGSize(width: 344, height: 54)
            : CGSize(width: 324, height: 52)
        let container = NSView(frame: CGRect(origin: .zero, size: size))
        view = container
        preferredContentSize = size

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10

        if tool == .mosaic {
            stack.addArrangedSubview(makeMosaicEffectRow())
            stack.addArrangedSubview(makeMosaicDrawingModeRow())
            stack.addArrangedSubview(separator())
            stack.addArrangedSubview(makeWidthRow())
        } else {
            stack.addArrangedSubview(makeWidthRow())
            stack.addArrangedSubview(separator())
            stack.addArrangedSubview(makeColorRow())
        }

        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        updateColorSelection()
    }

    private func makeColorRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 7

        for color in AnnotationColor.allCases {
            let button = ColorSwatchButton(title: "", target: self, action: #selector(selectColor(_:)))
            button.isBordered = false
            button.identifier = NSUserInterfaceItemIdentifier(color.rawValue)
            button.toolTip = color.displayName
            button.wantsLayer = true
            button.layer?.cornerRadius = 4
            button.layer?.cornerCurve = .continuous
            button.layer?.backgroundColor = color.nsColor.cgColor
            button.widthAnchor.constraint(equalToConstant: 22).isActive = true
            button.heightAnchor.constraint(equalToConstant: 22).isActive = true
            colorButtons[color] = button
            row.addArrangedSubview(button)
        }
        return row
    }

    private func makeWidthRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 0

        let values: [CGFloat] = [2, 4, 8]
        let diameters: [CGFloat] = [5, 9, 14]
        let names: [String]
        switch tool {
        case .text: names = ["小", "中", "大"]
        case .serial: names = ["小", "中", "大"]
        case .mosaic: names = ["低", "中", "高"]
        default: names = ["细", "中", "粗"]
        }
        let choices = NSStackView()
        choices.orientation = .horizontal
        choices.alignment = .centerY
        choices.spacing = 5
        for index in values.indices {
            let button = GlassToolbarButton()
            button.image = tool == .text
                ? Self.fontSizeImage(fontSize: [10, 14, 18][index])
                : Self.dotImage(diameter: diameters[index])
            button.imagePosition = .imageOnly
            button.identifier = NSUserInterfaceItemIdentifier(String(Double(values[index])))
            button.target = self
            button.action = #selector(selectWidth(_:))
            button.toolTip = "\(names[index])\(tool.widthLabel)"
            button.widthAnchor.constraint(equalToConstant: 34).isActive = true
            button.heightAnchor.constraint(equalToConstant: 28).isActive = true
            widthButtons[values[index]] = button
            choices.addArrangedSubview(button)
        }
        row.addArrangedSubview(choices)
        updateWidthSelection()
        return row
    }

    private func makeMosaicEffectRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 4
        let options: [(MosaicEffect, String, String, String)] = [
            (.pixelate, "mosaic-pixelate", "square.grid.3x3.fill", "像素马赛克"),
            (.blur, "mosaic-blur", "drop.fill", "高斯模糊")
        ]
        for (effect, icon, fallback, tooltip) in options {
            let button = mosaicOptionButton(
                icon: icon,
                fallbackSymbol: fallback,
                tooltip: tooltip,
                action: #selector(selectMosaicEffect(_:))
            )
            button.identifier = NSUserInterfaceItemIdentifier(effect.rawValue)
            button.showsSelection = mosaicConfiguration.effect == effect
            mosaicEffectButtons.append(button)
            row.addArrangedSubview(button)
        }
        return row
    }

    private func makeMosaicDrawingModeRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 4
        let options: [(MosaicDrawingMode, String, String, String)] = [
            (.brush, "mosaic-brush", "paintbrush.pointed.fill", "笔刷涂抹"),
            (.rectangle, "mosaic-rectangle", "rectangle.dashed", "矩形覆盖")
        ]
        for (mode, icon, fallback, tooltip) in options {
            let button = mosaicOptionButton(
                icon: icon,
                fallbackSymbol: fallback,
                tooltip: tooltip,
                action: #selector(selectMosaicDrawingMode(_:))
            )
            button.identifier = NSUserInterfaceItemIdentifier(mode.rawValue)
            button.showsSelection = mosaicConfiguration.drawingMode == mode
            mosaicDrawingModeButtons.append(button)
            row.addArrangedSubview(button)
        }
        return row
    }

    private func mosaicOptionButton(
        icon: String,
        fallbackSymbol: String,
        tooltip: String,
        action: Selector
    ) -> GlassToolbarButton {
        let button = GlassToolbarButton()
        button.image = mosaicIcon(named: icon, fallbackSymbol: fallbackSymbol)
        button.imagePosition = .imageOnly
        button.toolTip = tooltip
        button.target = self
        button.action = action
        button.widthAnchor.constraint(equalToConstant: 40).isActive = true
        button.heightAnchor.constraint(equalToConstant: 30).isActive = true
        return button
    }

    private func mosaicIcon(named name: String, fallbackSymbol: String) -> NSImage {
        let image = ToolbarIconProvider.image(named: name, accessibilityDescription: name)
            ?? NSImage(systemSymbolName: fallbackSymbol, accessibilityDescription: name)
            ?? NSImage(size: CGSize(width: 20, height: 20))
        image.size = CGSize(width: 19, height: 19)
        return image
    }

    private func separator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        separator.widthAnchor.constraint(equalToConstant: 1).isActive = true
        separator.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return separator
    }

    private func updateColorSelection() {
        for (color, button) in colorButtons {
            let selected = color == style.color
            button.layer?.borderWidth = selected ? 2.5 : 1
            button.layer?.borderColor = selected
                ? NSColor.controlAccentColor.cgColor
                : NSColor.separatorColor.cgColor
            button.layer?.shadowColor = selected ? NSColor.black.cgColor : nil
            button.layer?.shadowOpacity = selected ? 0.22 : 0
            button.layer?.shadowRadius = selected ? 2 : 0
        }
    }

    private func updateWidthSelection() {
        guard let selected = widthButtons.keys.min(by: {
            abs($0 - style.lineWidth) < abs($1 - style.lineWidth)
        }) else { return }
        for (width, button) in widthButtons {
            button.showsSelection = width == selected
        }
    }

    private static func dotImage(diameter: CGFloat) -> NSImage {
        let image = NSImage(size: CGSize(width: 18, height: 18), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: CGRect(
                x: rect.midX - diameter / 2,
                y: rect.midY - diameter / 2,
                width: diameter,
                height: diameter
            )).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func fontSizeImage(fontSize: CGFloat) -> NSImage {
        let image = NSImage(size: CGSize(width: 20, height: 20), flipped: false) { rect in
            let text = NSAttributedString(
                string: "A",
                attributes: [
                    .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                    .foregroundColor: NSColor.labelColor
                ]
            )
            let size = text.size()
            text.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
            return true
        }
        image.isTemplate = true
        return image
    }

    @objc private func selectColor(_ sender: NSButton) {
        guard let rawValue = sender.identifier?.rawValue,
              let color = AnnotationColor(rawValue: rawValue) else { return }
        style.color = color
        updateColorSelection()
        onChange(style)
    }

    @objc private func selectWidth(_ sender: NSButton) {
        guard let rawValue = sender.identifier?.rawValue,
              let value = Double(rawValue) else { return }
        style.lineWidth = CGFloat(value)
        updateWidthSelection()
        onChange(style)
    }

    @objc private func selectMosaicEffect(_ sender: NSButton) {
        guard let rawValue = sender.identifier?.rawValue,
              let effect = MosaicEffect(rawValue: rawValue) else { return }
        mosaicConfiguration.effect = effect
        for button in mosaicEffectButtons {
            button.showsSelection = button.identifier?.rawValue == rawValue
        }
        onMosaicChange(mosaicConfiguration)
    }

    @objc private func selectMosaicDrawingMode(_ sender: NSButton) {
        guard let rawValue = sender.identifier?.rawValue,
              let drawingMode = MosaicDrawingMode(rawValue: rawValue) else { return }
        mosaicConfiguration.drawingMode = drawingMode
        for button in mosaicDrawingModeButtons {
            button.showsSelection = button.identifier?.rawValue == rawValue
        }
        onMosaicChange(mosaicConfiguration)
    }
}

@MainActor
private final class ColorSwatchButton: NSButton {
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
            owner: self
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        if let toolTip, !toolTip.isEmpty {
            ScreenshotToolTipPresenter.shared.schedule(toolTip, for: self)
        }
    }

    override func mouseExited(with event: NSEvent) {
        ScreenshotToolTipPresenter.shared.hide(for: self)
    }

    override func mouseDown(with event: NSEvent) {
        ScreenshotToolTipPresenter.shared.hide(for: self)
        super.mouseDown(with: event)
    }
}

private extension EditorTool {
    var displayName: String {
        switch self {
        case .none: return "标注"
        case .rectangle: return "矩形"
        case .ellipse: return "圆形"
        case .pencil: return "铅笔"
        case .arrow: return "箭头"
        case .text: return "文字"
        case .serial: return "序号"
        case .mosaic: return "马赛克"
        case .magnifier: return "放大镜"
        }
    }

    var supportsColor: Bool { self != .mosaic }

    var widthLabel: String {
        switch self {
        case .text: return "字号"
        case .serial: return "大小"
        case .mosaic: return "强度"
        default: return "粗细"
        }
    }
}

private extension AnnotationColor {
    var displayName: String {
        switch self {
        case .red: return "红色"
        case .yellow: return "黄色"
        case .green: return "绿色"
        case .blue: return "蓝色"
        case .black: return "黑色"
        case .white: return "白色"
        }
    }
}
