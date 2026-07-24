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

    func testCaptureRegionUsesWindowWhenPointerIsInsideIt() throws {
        let display = CapturedDisplay(
            displayID: 3,
            screenFrame: CGRect(x: -200, y: 40, width: 200, height: 150),
            scale: 1,
            image: try makeImage(width: 200, height: 150),
            windows: [
                DetectedWindow(
                    windowID: 10,
                    ownerName: "Example",
                    frame: CGRect(x: -170, y: 60, width: 100, height: 80),
                    layer: 0
                )
            ]
        )

        XCTAssertEqual(
            display.localCaptureRegion(at: CGPoint(x: 50, y: 40)),
            CGRect(x: 30, y: 20, width: 100, height: 80)
        )
    }

    func testCaptureRegionFallsBackToWholeDisplay() throws {
        let display = CapturedDisplay(
            displayID: 4,
            screenFrame: CGRect(x: -200, y: 40, width: 200, height: 150),
            scale: 1,
            image: try makeImage(width: 200, height: 150),
            windows: [
                DetectedWindow(
                    windowID: 11,
                    ownerName: "Example",
                    frame: CGRect(x: -170, y: 60, width: 100, height: 80),
                    layer: 0
                )
            ]
        )

        XCTAssertEqual(
            display.localCaptureRegion(at: CGPoint(x: 170, y: 120)),
            CGRect(x: 0, y: 0, width: 200, height: 150)
        )
    }

    func testWindowOwnerProcessIdentifierUsesTopmostWindowAtPoint() throws {
        let display = CapturedDisplay(
            displayID: 5,
            screenFrame: CGRect(x: -200, y: 40, width: 200, height: 150),
            scale: 1,
            image: try makeImage(width: 200, height: 150),
            windows: [
                DetectedWindow(
                    windowID: 12,
                    ownerName: "Front",
                    ownerProcessIdentifier: 101,
                    frame: CGRect(x: -170, y: 60, width: 100, height: 80),
                    layer: 0
                ),
                DetectedWindow(
                    windowID: 13,
                    ownerName: "Back",
                    ownerProcessIdentifier: 202,
                    frame: CGRect(x: -180, y: 50, width: 130, height: 100),
                    layer: 0
                )
            ]
        )

        XCTAssertEqual(display.ownerProcessIdentifier(at: CGPoint(x: 50, y: 40)), 101)
        XCTAssertNil(display.ownerProcessIdentifier(at: CGPoint(x: 190, y: 140)))
    }

    func testPixelColorUsesCapturedImageAndFormatsHexValue() throws {
        let display = CapturedDisplay(
            displayID: 6,
            screenFrame: CGRect(x: 0, y: 0, width: 1, height: 1),
            scale: 2,
            image: try makeSolidImage(width: 2, height: 2, rgba: [0x12, 0x34, 0x56, 0xFF]),
            windows: []
        )

        let color = try XCTUnwrap(display.pixelColor(at: CGPoint(x: 0.75, y: 0.25)))
        XCTAssertEqual(color, CapturedPixelColor(red: 0x12, green: 0x34, blue: 0x56))
        XCTAssertEqual(color.hexString, "#123456")
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

    private func makeSolidImage(width: Int, height: Int, rgba: [UInt8]) throws -> CGImage {
        let data = Data(Array(repeating: rgba, count: width * height).flatMap { $0 })
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        return try XCTUnwrap(CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.union(
                CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
    }
}
