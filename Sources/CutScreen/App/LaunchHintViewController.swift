import AppKit

@MainActor
final class LaunchHintViewController: NSViewController {
    let shortcutLabel = NSTextField(labelWithString: "")
    let messageLabel = NSTextField(labelWithString: "按下快捷键即可呼出截图面板")
    let captureButton = NSButton(title: "立即截图", target: nil, action: nil)

    private let shortcut: String
    private let onCapture: () -> Void

    init(shortcut: String, onCapture: @escaping () -> Void) {
        self.shortcut = shortcut
        self.onCapture = onCapture
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = NSView(frame: CGRect(x: 0, y: 0, width: 300, height: 132))

        let icon = NSImageView()
        icon.image = ToolbarIconProvider.image(
            named: "status-viewfinder-bolt",
            accessibilityDescription: "轻截"
        )
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.contentTintColor = .systemGreen
        icon.widthAnchor.constraint(equalToConstant: 24).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 24).isActive = true

        let title = NSTextField(labelWithString: "轻截已在菜单栏运行")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = .labelColor

        let titleRow = NSStackView(views: [icon, title])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 8

        messageLabel.font = .systemFont(ofSize: 12)
        messageLabel.textColor = .secondaryLabelColor

        shortcutLabel.stringValue = shortcut
        shortcutLabel.font = .systemFont(ofSize: 13, weight: .medium)
        shortcutLabel.alignment = .left
        shortcutLabel.textColor = .labelColor

        captureButton.identifier = NSUserInterfaceItemIdentifier("launchHintCapture")
        captureButton.bezelStyle = .rounded
        captureButton.controlSize = .regular
        captureButton.target = self
        captureButton.action = #selector(capture)
        captureButton.toolTip = "立即开始截图"

        let actionRow = NSStackView(views: [shortcutLabel, NSView(), captureButton])
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 10

        let stack = NSStackView(views: [titleRow, messageLabel, actionRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -14),
            actionRow.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

        view = root
    }

    @objc private func capture() {
        onCapture()
    }
}
