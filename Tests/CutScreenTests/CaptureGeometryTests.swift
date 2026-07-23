import AppKit
import XCTest
@testable import CutScreen

final class CaptureGeometryTests: XCTestCase {
    func testSelectionAlignsToRetinaPixelGrid() throws {
        let display = CapturedDisplay(
            displayID: 1,
            screenFrame: CGRect(x: 0, y: 0, width: 200, height: 150),
            scale: 2,
            image: try makeImage(width: 400, height: 300),
            windows: []
        )

        let aligned = display.pixelAlignedLocalRect(
            CGRect(x: 10.24, y: 20.26, width: 100.25, height: 50.5)
        )
        XCTAssertEqual(aligned, CGRect(x: 10, y: 20, width: 100.5, height: 51))

        let cropped = try XCTUnwrap(display.crop(localRect: aligned))
        XCTAssertEqual(cropped.width, Int(aligned.width * display.scale))
        XCTAssertEqual(cropped.height, Int(aligned.height * display.scale))
    }

    func testSelectionAlignsToOneXPixelGridAndStaysInsideDisplay() throws {
        let display = CapturedDisplay(
            displayID: 2,
            screenFrame: CGRect(x: 0, y: 0, width: 120, height: 80),
            scale: 1,
            image: try makeImage(width: 120, height: 80),
            windows: []
        )

        let aligned = display.pixelAlignedLocalRect(
            CGRect(x: -0.4, y: 10.2, width: 120.8, height: 70.3)
        )
        XCTAssertEqual(aligned, CGRect(x: 0, y: 10, width: 120, height: 70))
    }

    private func makeImage(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try XCTUnwrap(context.makeImage())
    }
}
