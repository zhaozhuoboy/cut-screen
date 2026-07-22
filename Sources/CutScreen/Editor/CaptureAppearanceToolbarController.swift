import AppKit

@MainActor
final class CaptureAppearanceToolbarController: NSWindowController {
    private let onChange: (CaptureAppearance) -> Void
    private var appearance = CaptureAppearance()

    init(onChange: @escaping (CaptureAppearance) -> Void) {
        self.onChange = onChange
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 330, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        GlassToolbarComponents.configure(panel, cornerRadius: 13)
        super.init(window: panel)
        buildContent()
    }

    required init?(coder: NSCoder) { nil }

    func position(relativeTo selection: CGRect, in screenFrame: CGRect) {
        guard let window else { return }
        let margin: CGFloat = 10
        let visible = screenFrame.insetBy(dx: 8, dy: 8)
        var x = selection.midX - window.frame.width / 2
        x = min(max(x, visible.minX), visible.maxX - window.frame.width)

        var y = selection.maxY + margin
        if y + window.frame.height > visible.maxY {
            if selection.height >= window.frame.height + margin * 2 {
                y = selection.maxY - window.frame.height - margin
            } else {
                y = selection.minY - window.frame.height - margin
            }
        }
        y = min(max(y, visible.minY), visible.maxY - window.frame.height)
        window.setFrameOrigin(CGPoint(x: x, y: y))
    }

    private func buildContent() {
        guard let contentView = window?.contentView else { return }
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 7

        stack.addArrangedSubview(iconView(named: "corner-radius", description: "圆角"))
        let cornerLabel = label("圆角")
        stack.addArrangedSubview(cornerLabel)

        let cornerSlider = appearanceSlider(
            value: Double(appearance.cornerRadius),
            minimum: 0,
            maximum: Double(CaptureAppearance.maximumCornerRadius),
            toolTip: "拖动调整截图圆角",
            action: #selector(changeCornerRadius(_:))
        )
        cornerSlider.setAccessibilityLabel("截图圆角")
        stack.addArrangedSubview(cornerSlider)
        stack.addArrangedSubview(separator())

        stack.addArrangedSubview(iconView(named: "shadow", description: "阴影"))
        stack.addArrangedSubview(label("阴影"))
        let shadowSlider = appearanceSlider(
            value: Double(appearance.shadowStrength),
            minimum: 0,
            maximum: 1,
            toolTip: "拖动调整截图阴影强度，最左侧为无阴影",
            action: #selector(changeShadowStrength(_:))
        )
        shadowSlider.setAccessibilityLabel("截图阴影强度")
        stack.addArrangedSubview(shadowSlider)

        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])

        let fitting = stack.fittingSize
        window?.setContentSize(CGSize(width: fitting.width + 20, height: 44))
    }

    private func iconView(named name: String, description: String) -> NSImageView {
        let view = NSImageView()
        view.image = ToolbarIconProvider.image(named: name, accessibilityDescription: description)
        view.contentTintColor = .secondaryLabelColor
        view.widthAnchor.constraint(equalToConstant: 18).isActive = true
        view.heightAnchor.constraint(equalToConstant: 18).isActive = true
        return view
    }

    private func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: 1).isActive = true
        box.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return box
    }

    private func appearanceSlider(
        value: Double,
        minimum: Double,
        maximum: Double,
        toolTip: String,
        action: Selector
    ) -> NSSlider {
        let slider = NSSlider(value: value, minValue: minimum, maxValue: maximum, target: self, action: action)
        slider.isContinuous = true
        slider.controlSize = .small
        slider.toolTip = toolTip
        slider.widthAnchor.constraint(equalToConstant: 108).isActive = true
        return slider
    }

    @objc private func changeCornerRadius(_ sender: NSSlider) {
        appearance.cornerRadius = CGFloat(sender.doubleValue)
        onChange(appearance)
    }

    @objc private func changeShadowStrength(_ sender: NSSlider) {
        appearance.shadowStrength = CGFloat(sender.doubleValue)
        onChange(appearance)
    }
}
