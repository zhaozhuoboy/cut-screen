import AppKit

@MainActor
final class CaptureToolbarController: NSWindowController {
    struct Actions {
        var toolChanged: (EditorTool) -> Void
        var styleChanged: (AnnotationStyle) -> Void
        var undo: () -> Void
        var redo: () -> Void
        var scroll: () -> Void
        var pin: () -> Void
        var save: () -> Void
        var cancel: () -> Void
        var confirm: () -> Void
    }

    private let actions: Actions
    private var style = AnnotationStyle()
    private var toolButtons: [EditorTool: NSButton] = [:]
    private var colorButtons: [AnnotationColor: NSButton] = [:]
    private let scrollButton = NSButton()
    private let undoButton = NSButton()
    private let redoButton = NSButton()

    init(actions: Actions) {
        self.actions = actions
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 48),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        super.init(window: panel)
        buildContent()
    }

    required init?(coder: NSCoder) { nil }

    func position(relativeTo selection: CGRect, in screenFrame: CGRect) {
        guard let window else { return }
        let margin: CGFloat = 8
        let visible = screenFrame.insetBy(dx: 8, dy: 8)
        var x = selection.maxX - window.frame.width
        x = min(max(x, visible.minX), visible.maxX - window.frame.width)

        var y = selection.minY - window.frame.height - margin
        if y < visible.minY {
            y = selection.maxY + margin
        }
        y = min(max(y, visible.minY), visible.maxY - window.frame.height)
        window.setFrameOrigin(CGPoint(x: x, y: y))
    }

    func setTool(_ tool: EditorTool) {
        for (candidate, button) in toolButtons {
            let selected = candidate == tool
            button.contentTintColor = selected ? .systemGreen : .labelColor
            button.state = selected ? .on : .off
            button.wantsLayer = true
            button.layer?.backgroundColor = selected
                ? NSColor.systemGreen.withAlphaComponent(0.15).cgColor
                : NSColor.clear.cgColor
            button.layer?.cornerRadius = 6
        }
    }

    func setHistory(canUndo: Bool, canRedo: Bool) {
        undoButton.isEnabled = canUndo
        redoButton.isEnabled = canRedo
    }

    func setScrollEnabled(_ enabled: Bool) {
        scrollButton.isEnabled = enabled
    }

    private func buildContent() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor
        contentView.layer?.cornerRadius = 9
        contentView.layer?.borderWidth = 0.5
        contentView.layer?.borderColor = NSColor.separatorColor.cgColor

        let toolStack = NSStackView()
        toolStack.orientation = .horizontal
        toolStack.alignment = .centerY
        toolStack.spacing = 2

        addTool(.rectangle, icon: "rectangle", tooltip: "矩形", to: toolStack)
        addTool(.ellipse, icon: "ellipse", tooltip: "圆形", to: toolStack)
        addTool(.pencil, icon: "pencil", tooltip: "铅笔", to: toolStack)
        addTool(.arrow, icon: "arrow", tooltip: "箭头", to: toolStack)
        addTool(.serial, icon: "serial", tooltip: "序号", to: toolStack)
        addTool(.mosaic, icon: "mosaic", tooltip: "马赛克", to: toolStack)
        toolStack.addArrangedSubview(separator())

        for color in AnnotationColor.allCases {
            let button = NSButton(title: "●", target: self, action: #selector(selectColor(_:)))
            button.isBordered = false
            button.font = .systemFont(ofSize: 17)
            button.attributedTitle = NSAttributedString(
                string: "●",
                attributes: [.foregroundColor: color.nsColor]
            )
            button.identifier = NSUserInterfaceItemIdentifier(color.rawValue)
            button.toolTip = color.rawValue
            button.widthAnchor.constraint(equalToConstant: 20).isActive = true
            colorButtons[color] = button
            toolStack.addArrangedSubview(button)
        }

        let widths = NSSegmentedControl(labels: ["细", "中", "粗"], trackingMode: .selectOne, target: self, action: #selector(selectWidth(_:)))
        widths.selectedSegment = 1
        widths.controlSize = .small
        widths.toolTip = "线宽"
        toolStack.addArrangedSubview(widths)
        toolStack.addArrangedSubview(separator())

        configureActionButton(undoButton, icon: "undo", tooltip: "撤销 ⌘Z", action: #selector(undo))
        configureActionButton(redoButton, icon: "redo", tooltip: "重做 ⇧⌘Z", action: #selector(redo))
        undoButton.isEnabled = false
        redoButton.isEnabled = false
        toolStack.addArrangedSubview(undoButton)
        toolStack.addArrangedSubview(redoButton)

        configureActionButton(scrollButton, icon: "scroll", tooltip: "滚动长截图", action: #selector(scroll))
        toolStack.addArrangedSubview(scrollButton)
        toolStack.addArrangedSubview(actionButton(icon: "pin", tooltip: "钉在桌面", action: #selector(pin)))
        toolStack.addArrangedSubview(actionButton(icon: "save", tooltip: "保存到本地", action: #selector(save)))
        toolStack.addArrangedSubview(actionButton(icon: "cancel", tooltip: "取消 Esc", action: #selector(cancel)))

        let confirm = actionButton(icon: "confirm", tooltip: "复制到剪贴板", action: #selector(confirm))
        confirm.contentTintColor = .white
        confirm.wantsLayer = true
        confirm.layer?.backgroundColor = NSColor.systemGreen.cgColor
        confirm.layer?.cornerRadius = 6
        toolStack.addArrangedSubview(confirm)

        toolStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(toolStack)
        NSLayoutConstraint.activate([
            toolStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            toolStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            toolStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            toolStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6)
        ])

        let fitting = toolStack.fittingSize
        window?.setContentSize(CGSize(width: fitting.width + 16, height: 48))
        setTool(.none)
        updateColorSelection()
    }

    private func addTool(_ tool: EditorTool, icon: String, tooltip: String, to stack: NSStackView) {
        let button = actionButton(icon: icon, tooltip: tooltip, action: #selector(selectTool(_:)))
        button.identifier = NSUserInterfaceItemIdentifier(tool.rawValue)
        button.setButtonType(.toggle)
        toolButtons[tool] = button
        stack.addArrangedSubview(button)
    }

    private func actionButton(icon: String, tooltip: String, action: Selector) -> NSButton {
        let button = NSButton()
        configureActionButton(button, icon: icon, tooltip: tooltip, action: action)
        return button
    }

    private func configureActionButton(_ button: NSButton, icon: String, tooltip: String, action: Selector) {
        button.image = ToolbarIconProvider.image(named: icon, accessibilityDescription: tooltip)
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.target = self
        button.action = action
        button.toolTip = tooltip
        button.widthAnchor.constraint(equalToConstant: 30).isActive = true
        button.heightAnchor.constraint(equalToConstant: 30).isActive = true
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: 1).isActive = true
        box.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return box
    }

    private func updateColorSelection() {
        for (color, button) in colorButtons {
            button.wantsLayer = true
            button.layer?.backgroundColor = color == style.color ? NSColor.selectedControlColor.withAlphaComponent(0.22).cgColor : NSColor.clear.cgColor
            button.layer?.cornerRadius = 4
        }
    }

    @objc private func selectTool(_ sender: NSButton) {
        guard let rawValue = sender.identifier?.rawValue, let tool = EditorTool(rawValue: rawValue) else { return }
        let selected = sender.state == .on ? tool : .none
        setTool(selected)
        actions.toolChanged(selected)
    }

    @objc private func selectColor(_ sender: NSButton) {
        guard let rawValue = sender.identifier?.rawValue, let color = AnnotationColor(rawValue: rawValue) else { return }
        style.color = color
        updateColorSelection()
        actions.styleChanged(style)
    }

    @objc private func selectWidth(_ sender: NSSegmentedControl) {
        let values: [CGFloat] = [2, 4, 8]
        style.lineWidth = values[max(0, min(sender.selectedSegment, values.count - 1))]
        actions.styleChanged(style)
    }

    @objc private func undo() { actions.undo() }
    @objc private func redo() { actions.redo() }
    @objc private func scroll() { actions.scroll() }
    @objc private func pin() { actions.pin() }
    @objc private func save() { actions.save() }
    @objc private func cancel() { actions.cancel() }
    @objc private func confirm() { actions.confirm() }
}
