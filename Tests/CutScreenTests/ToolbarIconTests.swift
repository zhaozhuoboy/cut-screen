import AppKit
import XCTest
@testable import CutScreen

@MainActor
final class ToolbarIconTests: XCTestCase {
    func testAllToolbarIconsLoadAsVectorImages() throws {
        let names = [
            "rectangle", "ellipse", "pencil", "arrow", "serial", "mosaic",
            "undo", "redo", "scroll", "pin", "save", "cancel", "confirm"
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
}
