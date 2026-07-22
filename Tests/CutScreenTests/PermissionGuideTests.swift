import AppKit
import XCTest
@testable import CutScreen

@MainActor
final class PermissionGuideTests: XCTestCase {
    func testGuideStaysHiddenWhenPermissionAlreadyExists() {
        let controller = ScreenCapturePermissionGuideController(
            hasPermission: { true },
            requestPermission: { true },
            openSettings: {}
        )

        controller.presentIfNeeded()

        XCTAssertFalse(controller.window?.isVisible == true)
    }

    func testPrimaryButtonRequestsPermissionAndOpensSettingsWhenDenied() throws {
        var requestCount = 0
        var openSettingsCount = 0
        let controller = ScreenCapturePermissionGuideController(
            hasPermission: { false },
            requestPermission: {
                requestCount += 1
                return false
            },
            openSettings: { openSettingsCount += 1 }
        )
        controller.presentIfNeeded()
        let contentView = try XCTUnwrap(controller.window?.contentView)
        let requestButton = try XCTUnwrap(findButton(
            in: contentView,
            identifier: "requestScreenCapturePermission"
        ))

        requestButton.performClick(nil)

        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(openSettingsCount, 1)
        controller.close()
    }

    private func findButton(in view: NSView, identifier: String) -> NSButton? {
        if let button = view as? NSButton, button.identifier?.rawValue == identifier {
            return button
        }
        for subview in view.subviews {
            if let button = findButton(in: subview, identifier: identifier) { return button }
        }
        return nil
    }
}
