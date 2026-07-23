import AppKit
import XCTest
@testable import CutScreen

@MainActor
final class ToolbarIconTests: XCTestCase {
    func testGlassToolbarUsesRoundedContentMask() {
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 200, height: 52),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        let content = GlassToolbarComponents.configure(panel, cornerRadius: 14)
        content.layoutSubtreeIfNeeded()

        XCTAssertEqual(content.layer?.cornerRadius, 14)
        XCTAssertTrue(content.layer?.masksToBounds == true)
        XCTAssertNotNil(content.layer?.mask)
    }

    func testAllToolbarIconsLoadAsVectorImages() throws {
        let names = [
            "rectangle", "ellipse", "pencil", "arrow", "text", "serial", "mosaic", "magnifier",
            "undo", "redo", "scroll", "pin", "save", "cancel", "confirm",
            "corner-radius", "shadow", "mosaic-pixelate", "mosaic-blur",
            "mosaic-brush", "mosaic-rectangle", "status-viewfinder-bolt"
        ]
        for name in names {
            let image = try XCTUnwrap(
                ToolbarIconProvider.image(named: name, accessibilityDescription: name),
                "Missing icon: \(name)"
            )
            XCTAssertTrue(image.isTemplate)
            XCTAssertEqual(image.size, CGSize(width: 20, height: 20))
        }
    }

    func testLaunchHintShowsShortcutAndStartsCapture() {
        var didCapture = false
        let controller = LaunchHintViewController(shortcut: "⌃⌘A") {
            didCapture = true
        }
        controller.loadViewIfNeeded()

        XCTAssertEqual(controller.shortcutLabel.stringValue, "⌃⌘A")
        XCTAssertEqual(controller.messageLabel.stringValue, "按下快捷键即可呼出截图面板")
        XCTAssertEqual(
            controller.captureButton.identifier,
            NSUserInterfaceItemIdentifier("launchHintCapture")
        )

        controller.captureButton.performClick(nil)
        XCTAssertTrue(didCapture)
    }
}
