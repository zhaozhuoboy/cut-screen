import AppKit
import XCTest
@testable import CutScreen

@MainActor
final class CaptureDocumentTests: XCTestCase {
    func testUndoRedoAndSerialNumber() throws {
        let document = CaptureDocument(frame: try makeFrame())
        document.add(Annotation(kind: .serial(center: CGPoint(x: 10, y: 10), number: 1), style: .init()))
        document.add(Annotation(kind: .rectangle(CGRect(x: 2, y: 2, width: 10, height: 8)), style: .init()))

        XCTAssertEqual(document.annotations.count, 2)
        XCTAssertEqual(document.nextSerialNumber, 2)
        document.undo()
        XCTAssertEqual(document.annotations.count, 1)
        XCTAssertTrue(document.canRedo)
        document.redo()
        XCTAssertEqual(document.annotations.count, 2)
    }

    func testDeletingSerialDoesNotRenumberFutureSerialsWhileHigherNumberExists() throws {
        let document = CaptureDocument(frame: try makeFrame())
        let first = Annotation(kind: .serial(center: .zero, number: 1), style: .init())
        let third = Annotation(kind: .serial(center: CGPoint(x: 20, y: 20), number: 3), style: .init())
        document.add(first)
        document.add(third)
        document.remove(id: first.id)
        XCTAssertEqual(document.nextSerialNumber, 4)
    }

    func testAnnotationTranslation() {
        let annotation = Annotation(
            kind: .arrow(start: CGPoint(x: 1, y: 2), end: CGPoint(x: 5, y: 8)),
            style: .init()
        )
        let translated = annotation.kind.translated(by: CGPoint(x: 3, y: -1))
        XCTAssertEqual(translated, .arrow(start: CGPoint(x: 4, y: 1), end: CGPoint(x: 8, y: 7)))
    }

    func testPNGExportHasExpectedDimensions() throws {
        let document = CaptureDocument(frame: try makeFrame(width: 32, height: 24))
        document.add(Annotation(kind: .ellipse(CGRect(x: 2, y: 2, width: 12, height: 9)), style: .init()))
        let exporter = ImageExporter()
        let data = try exporter.data(for: document, format: .png)
        let representation = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(representation.pixelsWide, 32)
        XCTAssertEqual(representation.pixelsHigh, 24)
    }

    func testExportPreservesBaseImageOrientation() throws {
        let image = makeGradientImage(width: 20, height: 16)
        let document = CaptureDocument(frame: CapturedFrame(
            image: image,
            pointSize: CGSize(width: 20, height: 16),
            scale: 1
        ))
        let rendered = try ImageExporter().render(document)
        let originalGray = GrayFrame(image: image, targetWidth: 20, maximumHeight: 16)
        let renderedGray = GrayFrame(image: rendered, targetWidth: 20, maximumHeight: 16)
        XCTAssertLessThan(GrayFrameMatcher.meanDifference(originalGray, renderedGray, shift: 0), 2)
    }

    private func makeFrame(width: Int = 40, height: Int = 30) throws -> CapturedFrame {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return CapturedFrame(
            image: try XCTUnwrap(context.makeImage()),
            pointSize: CGSize(width: width, height: height),
            scale: 1
        )
    }


    private func makeGradientImage(width: Int, height: Int) -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for row in 0..<height {
            for column in 0..<width {
                let offset = (row * width + column) * 4
                bytes[offset] = UInt8((row * 13 + column * 3) % 240)
                bytes[offset + 1] = UInt8((row * 7 + column * 11) % 240)
                bytes[offset + 2] = UInt8((row * 17 + column * 5) % 240)
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue).union(.byteOrder32Big),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }
}
