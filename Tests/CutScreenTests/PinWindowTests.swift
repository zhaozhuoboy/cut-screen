import AppKit
import XCTest
@testable import CutScreen

@MainActor
final class PinWindowTests: XCTestCase {
    func testPinnedImageUsesStyledCardLayout() throws {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 120,
            height: 80,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(NSColor.systemGreen.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
        let image = try XCTUnwrap(context.makeImage())
        let manager = PinManager()

        manager.pin(image, pointSize: CGSize(width: 120, height: 80))

        let window = try XCTUnwrap(NSApplication.shared.windows.first(where: { $0.title == "轻截贴图" }))
        let content = try XCTUnwrap(window.contentView)
        content.layoutSubtreeIfNeeded()
        let imageView = try XCTUnwrap(content.subviews.first(where: {
            $0.identifier?.rawValue == "pinnedImage"
        }))

        XCTAssertFalse(window.styleMask.contains(.titled))
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertEqual(content.layer?.cornerRadius, 12)
        XCTAssertEqual(imageView.frame.width, 120, accuracy: 0.5)
        XCTAssertEqual(imageView.frame.height, 80, accuracy: 0.5)
        XCTAssertNotNil(content.subviews.first(where: {
            $0.identifier?.rawValue == "pinnedImageHeader"
        }))

        window.close()
    }
}
