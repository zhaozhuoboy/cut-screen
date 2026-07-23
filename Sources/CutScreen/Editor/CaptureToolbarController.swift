import AppKit

@MainActor
final class CaptureToolbarController: NSWindowController {
    struct Actions {
        var toolChanged: (EditorTool) -> Void
        var styleChanged: (AnnotationStyle) -> Void
        var mosaicConfigurationChanged: (MosaicConfiguration) -> Void
        var undo: () -> Void
        var redo: () -> Void
        var scroll: () -> Void
        var pin: () -> Void
        var save: () -> Void
        var cancel: () -> Void
        var confirm: () -> Void
    }

    private let actions: Actions
    private var activeTool: EditorTool = .none
    private var toolStyles = Dictionary(
        uniqueKeysWithValues: EditorTool.allCases
            .filter { $0 != .none }
            .map { ($0, AnnotationStyle()) }
    )
    private var mosaicConfiguration = MosaicConfiguration()
    private var toolButtons: [EditorTool: GlassToolbarButton] = [:]
    private var stylePanel: NSPanel?
    private var styleViewController: ToolStyleViewController?
    private var captureScreenFrame = CGRect.zero
    private var toolbarIsBelowSelection = true
    private let scrollButton = GlassToolbarButton()
    private let undoButton = GlassToolbarButton()
    private let redoButton = GlassToolbarButton()

    init(actions: Actions) {
        self.actions = actions
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 52),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        GlassToolbarComponents.configure(panel)
        super.init(window: panel)
        buildContent()
    }

    required init?(coder: NSCoder) { nil }

    override func close() {
        ScreenshotToolTipPresenter.shared.hide()
        hideStylePanel()
        super.close()
    }

    func position(relativeTo selection: CGRect, in screenFrame: CGRect) {
        guard let window else { return }
        captureScreenFrame = screenFrame
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
        toolbarIsBelowSelection = window.frame.maxY <= selection.minY
        positionStylePanel()
    }

    func setTool(_ tool: EditorTool) {
        activeTool = tool
        for (candidate, button) in toolButtons {
            let selected = candidate == tool
            button.state = selected ? .on : .off
            button.showsSelection = selected
        }
    }

    func setHistory(canUndo: Bool, canRedo: Bool) {
        undoButton.isEnabled = canUndo
        redoButton.isEnabled = canRedo
    }

    func setScrollEnabled(_ enabled: Bool) {
        scrollButton.isEnabled = enabled
    }

    func hideStylePanel() {
        ScreenshotToolTipPresenter.shared.hide()
        stylePanel?.orderOut(nil)
        stylePanel = nil
        styleViewController = nil
    }

    private func buildContent() {
        guard let contentView = window?.contentView else { return }

        let toolStack = NSStackView()
        toolStack.orientation = .horizontal
        toolStack.alignment = .centerY
        toolStack.spacing = 2

        addTool(.rectangle, icon: "rectangle", tooltip: "矩形", to: toolStack)
        addTool(.ellipse, icon: "ellipse", tooltip: "圆形", to: toolStack)
        addTool(.pencil, icon: "pencil", tooltip: "铅笔", to: toolStack)
        addTool(.arrow, icon: "arrow", tooltip: "箭头", to: toolStack)
        addTool(.text, icon: "text", tooltip: "文字", to: toolStack)
        addTool(.serial, icon: "serial", tooltip: "序号", to: toolStack)
        addTool(.mosaic, icon: "mosaic", tooltip: "马赛克", to: toolStack)
        addTool(.magnifier, icon: "magnifier", tooltip: "放大镜", to: toolStack)
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
        confirm.isPrimaryAction = true
        toolStack.addArrangedSubview(confirm)

        toolStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(toolStack)
        NSLayoutConstraint.activate([
            toolStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            toolStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            toolStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            toolStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])

        let fitting = toolStack.fittingSize
        window?.setContentSize(CGSize(width: fitting.width + 16, height: 52))
        setTool(.none)
    }

    private func addTool(_ tool: EditorTool, icon: String, tooltip: String, to stack: NSStackView) {
        let button = actionButton(icon: icon, tooltip: tooltip, action: #selector(selectTool(_:)))
        button.identifier = NSUserInterfaceItemIdentifier(tool.rawValue)
        button.setButtonType(.toggle)
        toolButtons[tool] = button
        stack.addArrangedSubview(button)
    }

    private func actionButton(icon: String, tooltip: String, action: Selector) -> GlassToolbarButton {
        let button = GlassToolbarButton()
        configureActionButton(button, icon: icon, tooltip: tooltip, action: action)
        return button
    }

    private func configureActionButton(_ button: GlassToolbarButton, icon: String, tooltip: String, action: Selector) {
        button.image = ToolbarIconProvider.image(named: icon, accessibilityDescription: tooltip)
        button.imagePosition = .imageOnly
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

    @objc private func selectTool(_ sender: NSButton) {
        guard let rawValue = sender.identifier?.rawValue, let tool = EditorTool(rawValue: rawValue) else { return }
        let style = toolStyles[tool] ?? AnnotationStyle()
        setTool(tool)
        actions.styleChanged(style)
        if tool == .mosaic {
            actions.mosaicConfigurationChanged(mosaicConfiguration)
        }
        actions.toolChanged(tool)
        if tool == .magnifier {
            hideStylePanel()
        } else {
            showStylePanel(for: tool)
        }
    }

    private func showStylePanel(for tool: EditorTool) {
        hideStylePanel()
        let controller = ToolStyleViewController(
            tool: tool,
            style: toolStyles[tool] ?? AnnotationStyle(),
            mosaicConfiguration: mosaicConfiguration,
            onChange: { [weak self] style in
                guard let self else { return }
                self.toolStyles[tool] = style
                if self.activeTool == tool { self.actions.styleChanged(style) }
            },
            onMosaicChange: { [weak self] configuration in
                guard let self else { return }
                self.mosaicConfiguration = configuration
                if self.activeTool == .mosaic {
                    self.actions.mosaicConfigurationChanged(configuration)
                }
            }
        )
        _ = controller.view
        let size = controller.preferredContentSize
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .utilityWindow
        let glass = GlassToolbarComponents.configure(panel, cornerRadius: 12)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        glass.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: glass.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: glass.bottomAnchor)
        ])
        styleViewController = controller
        stylePanel = panel
        positionStylePanel()
        panel.orderFrontRegardless()
    }

    private func positionStylePanel() {
        guard let panel = stylePanel,
              let toolbarWindow = window,
              let button = toolButtons[activeTool],
              let buttonWindow = button.window else { return }

        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = (captureScreenFrame.isEmpty ? toolbarWindow.screen?.visibleFrame ?? toolbarWindow.frame : captureScreenFrame)
            .insetBy(dx: 8, dy: 8)
        var x = buttonRect.minX - 8
        x = min(max(x, visible.minX), visible.maxX - panel.frame.width)

        let preferredY = toolbarIsBelowSelection
            ? toolbarWindow.frame.minY - panel.frame.height - 6
            : toolbarWindow.frame.maxY + 6
        var y = preferredY
        if y < visible.minY || y + panel.frame.height > visible.maxY {
            y = toolbarIsBelowSelection
                ? toolbarWindow.frame.maxY + 6
                : toolbarWindow.frame.minY - panel.frame.height - 6
        }
        y = min(max(y, visible.minY), visible.maxY - panel.frame.height)
        panel.setFrameOrigin(CGPoint(x: x, y: y))
    }

    @objc private func undo() { actions.undo() }
    @objc private func redo() { actions.redo() }
    @objc private func scroll() { hideStylePanel(); actions.scroll() }
    @objc private func pin() { hideStylePanel(); actions.pin() }
    @objc private func save() { hideStylePanel(); actions.save() }
    @objc private func cancel() { hideStylePanel(); actions.cancel() }
    @objc private func confirm() { hideStylePanel(); actions.confirm() }
}
