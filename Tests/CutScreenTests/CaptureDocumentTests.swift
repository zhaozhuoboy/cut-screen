import AppKit
import XCTest
@testable import CutScreen

@MainActor
final class CaptureDocumentTests: XCTestCase {
    func testUndoRedoAndSerialNumber() throws {
        let document = CaptureDocument(frame: try makeFrame())
        document.add(Annotation(kind: .serial(center: CGPoint(x: 10, y: 10), number: 1, text: "第一步"), style: .init()))
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
        let first = Annotation(kind: .serial(center: .zero, number: 1, text: ""), style: .init())
        let third = Annotation(kind: .serial(center: CGPoint(x: 20, y: 20), number: 3, text: "第三步"), style: .init())
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

    func testSerialTextMovesWithMarker() {
        let annotation = Annotation(
            kind: .serial(center: CGPoint(x: 12, y: 14), number: 2, text: "打开设置"),
            style: .init()
        )
        XCTAssertEqual(
            annotation.kind.translated(by: CGPoint(x: 5, y: -3)),
            .serial(center: CGPoint(x: 17, y: 11), number: 2, text: "打开设置")
        )
    }

    func testSerialMarkerIsCompactAndNoteTextIsMoreReadable() {
        XCTAssertEqual(SerialAnnotationMetrics.radius(lineWidth: 4), 11)
        XCTAssertEqual(SerialAnnotationMetrics.numberFontSize(lineWidth: 4), 11)
        XCTAssertEqual(SerialAnnotationMetrics.noteFontSize(lineWidth: 4), 14)
        XCTAssertGreaterThan(SerialAnnotationMetrics.renderedNoteVerticalOffset, 0)
        XCTAssertLessThan(SerialAnnotationMetrics.editorVerticalOffset, 0)
    }

    func testEveryAnnotationKindCanBeTranslated() {
        let kinds: [AnnotationKind] = [
            .rectangle(CGRect(x: 1, y: 2, width: 8, height: 7)),
            .ellipse(CGRect(x: 2, y: 3, width: 9, height: 6)),
            .pencil([CGPoint(x: 3, y: 4), CGPoint(x: 8, y: 9)]),
            .arrow(start: CGPoint(x: 4, y: 5), end: CGPoint(x: 10, y: 12)),
            .serial(center: CGPoint(x: 14, y: 16), number: 1, text: "说明"),
            .magnifier(rect: CGRect(x: 6, y: 7, width: 18, height: 16), zoom: 2),
            .mosaic(MosaicAnnotation(
                effect: .pixelate,
                shape: .brush([CGPoint(x: 5, y: 6), CGPoint(x: 11, y: 13)])
            ))
        ]

        for kind in kinds {
            let moved = kind.translated(by: CGPoint(x: 7, y: -3))
            XCTAssertEqual(moved.bounds.minX, kind.bounds.minX + 7, accuracy: 0.001)
            XCTAssertEqual(moved.bounds.minY, kind.bounds.minY - 3, accuracy: 0.001)
        }
    }

    func testRectangleAndEllipseCanBeSelectedFromTheirInterior() {
        let style = AnnotationStyle()
        let rectangle = Annotation(kind: .rectangle(CGRect(x: 0, y: 0, width: 40, height: 30)), style: style)
        let ellipse = Annotation(kind: .ellipse(CGRect(x: 0, y: 0, width: 40, height: 30)), style: style)

        XCTAssertTrue(AnnotationPainter.hitTest(rectangle, point: CGPoint(x: 20, y: 15)))
        XCTAssertTrue(AnnotationPainter.hitTest(ellipse, point: CGPoint(x: 20, y: 15)))
    }

    func testMosaicRectangleCanBeSelectedAndTranslated() {
        let original = MosaicAnnotation(
            effect: .blur,
            shape: .rectangle(CGRect(x: 8, y: 10, width: 24, height: 18))
        )
        let annotation = Annotation(kind: .mosaic(original), style: .init(lineWidth: 4))

        XCTAssertTrue(AnnotationPainter.hitTest(annotation, point: CGPoint(x: 20, y: 18)))
        XCTAssertEqual(
            annotation.kind.translated(by: CGPoint(x: 5, y: -2)),
            .mosaic(MosaicAnnotation(
                effect: .blur,
                shape: .rectangle(CGRect(x: 13, y: 8, width: 24, height: 18))
            ))
        )
    }

    func testMosaicAndBlurRectangleAffectOnlySelectedArea() throws {
        let base = makeGradientImage(width: 80, height: 60)
        let outsideRect = CGRect(x: 0, y: 0, width: 8, height: 8)

        for effect in [MosaicEffect.pixelate, .blur] {
            let document = CaptureDocument(frame: CapturedFrame(
                image: base,
                pointSize: CGSize(width: 80, height: 60),
                scale: 1
            ))
            document.setAppearance(CaptureAppearance(cornerRadius: 0, hasShadow: false))
            document.add(Annotation(
                kind: .mosaic(MosaicAnnotation(
                    effect: effect,
                    shape: .rectangle(CGRect(x: 20, y: 15, width: 40, height: 30))
                )),
                style: .init(lineWidth: 8)
            ))

            let rendered = try ImageExporter().render(document)
            let baseGray = GrayFrame(image: base, targetWidth: 80, maximumHeight: 60)
            let renderedGray = GrayFrame(image: rendered, targetWidth: 80, maximumHeight: 60)
            XCTAssertGreaterThan(
                GrayFrameMatcher.meanDifference(baseGray, renderedGray, shift: 0),
                0.5,
                "\(effect) should visibly alter the selected rectangle"
            )

            let baseOutside = try XCTUnwrap(base.cropping(to: outsideRect))
            let renderedOutside = try XCTUnwrap(rendered.cropping(to: outsideRect))
            let baseOutsideGray = GrayFrame(image: baseOutside, targetWidth: 8, maximumHeight: 8)
            let renderedOutsideGray = GrayFrame(image: renderedOutside, targetWidth: 8, maximumHeight: 8)
            XCTAssertLessThan(
                GrayFrameMatcher.meanDifference(baseOutsideGray, renderedOutsideGray, shift: 0),
                0.1,
                "\(effect) should not alter pixels outside the selected rectangle"
            )
        }
    }

    func testMagnifierChangesOnlyLensArea() throws {
        let base = makeGradientImage(width: 80, height: 60)
        let document = CaptureDocument(frame: CapturedFrame(
            image: base,
            pointSize: CGSize(width: 80, height: 60),
            scale: 1
        ))
        document.setAppearance(CaptureAppearance(cornerRadius: 0, hasShadow: false))
        let lens = Annotation(
            kind: .magnifier(rect: CGRect(x: 20, y: 15, width: 40, height: 30), zoom: 2),
            style: .init(color: .green, lineWidth: 4)
        )
        document.add(lens)

        XCTAssertTrue(AnnotationPainter.hitTest(lens, point: CGPoint(x: 40, y: 30)))
        let rendered = try ImageExporter().render(document)

        let insideRect = CGRect(x: 30, y: 22, width: 20, height: 16)
        let baseInside = try XCTUnwrap(base.cropping(to: insideRect))
        let renderedInside = try XCTUnwrap(rendered.cropping(to: insideRect))
        XCTAssertGreaterThan(
            GrayFrameMatcher.meanDifference(
                GrayFrame(image: baseInside, targetWidth: 20, maximumHeight: 16),
                GrayFrame(image: renderedInside, targetWidth: 20, maximumHeight: 16),
                shift: 0
            ),
            1
        )

        let outsideRect = CGRect(x: 0, y: 0, width: 8, height: 8)
        let baseOutside = try XCTUnwrap(base.cropping(to: outsideRect))
        let renderedOutside = try XCTUnwrap(rendered.cropping(to: outsideRect))
        XCTAssertLessThan(
            GrayFrameMatcher.meanDifference(
                GrayFrame(image: baseOutside, targetWidth: 8, maximumHeight: 8),
                GrayFrame(image: renderedOutside, targetWidth: 8, maximumHeight: 8),
                shift: 0
            ),
            0.1
        )
    }

    func testMagnifierUsesFixedOutlineInsteadOfAnnotationStyle() throws {
        let base = makeGradientImage(width: 60, height: 44)
        func rendered(style: AnnotationStyle) throws -> CGImage {
            let document = CaptureDocument(frame: CapturedFrame(
                image: base,
                pointSize: CGSize(width: 60, height: 44),
                scale: 1
            ))
            document.setAppearance(CaptureAppearance(cornerRadius: 0, hasShadow: false))
            document.add(Annotation(
                kind: .magnifier(rect: CGRect(x: 12, y: 10, width: 30, height: 24), zoom: 2),
                style: style
            ))
            return try ImageExporter().render(document)
        }

        let thinRed = try rendered(style: .init(color: .red, lineWidth: 2))
        let thickBlue = try rendered(style: .init(color: .blue, lineWidth: 8))
        XCTAssertLessThan(
            GrayFrameMatcher.meanDifference(
                GrayFrame(image: thinRed, targetWidth: 60, maximumHeight: 44),
                GrayFrame(image: thickBlue, targetWidth: 60, maximumHeight: 44),
                shift: 0
            ),
            0.1
        )
    }

    func testPNGExportHasExpectedDimensions() throws {
        let document = CaptureDocument(frame: try makeFrame(width: 32, height: 24))
        document.setAppearance(CaptureAppearance(cornerRadius: 0, hasShadow: false))
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
        document.setAppearance(CaptureAppearance(cornerRadius: 0, hasShadow: false))
        let rendered = try ImageExporter().render(document)
        let originalGray = GrayFrame(image: image, targetWidth: 20, maximumHeight: 16)
        let renderedGray = GrayFrame(image: rendered, targetWidth: 20, maximumHeight: 16)
        XCTAssertLessThan(GrayFrameMatcher.meanDifference(originalGray, renderedGray, shift: 0), 2)
    }

    func testRoundedExportKeepsDimensionsAndMakesCornersTransparent() throws {
        let document = CaptureDocument(frame: try makeFrame(width: 40, height: 30))
        document.setAppearance(CaptureAppearance(cornerRadius: 8, hasShadow: false))

        let rendered = try ImageExporter().render(document)

        XCTAssertEqual(rendered.width, 40)
        XCTAssertEqual(rendered.height, 30)
        XCTAssertEqual(alpha(of: rendered, x: 0, y: 0), 0)
        XCTAssertEqual(alpha(of: rendered, x: 20, y: 15), 255)
    }

    func testNewDocumentUsesRoundedCornersAndShadowByDefault() throws {
        let document = CaptureDocument(frame: try makeFrame(width: 40, height: 30))

        XCTAssertEqual(document.appearance.cornerRadius, 16)
        XCTAssertTrue(document.appearance.hasShadow)
        XCTAssertEqual(document.appearance.shadowStrength, 0.75)
    }

    func testAppearanceSlidersUseContinuousCornerAndShadowValues() {
        let appearance = CaptureAppearance(cornerRadius: 13.5, shadowStrength: 0.4)

        XCTAssertEqual(appearance.cornerRadius, 13.5)
        XCTAssertEqual(appearance.normalizedShadowStrength, 0.4)
        XCTAssertTrue(appearance.hasShadow)
        XCTAssertGreaterThan(appearance.shadowBlurRadius, 6)
        XCTAssertGreaterThan(appearance.shadowPadding, 6)
        XCTAssertFalse(CaptureAppearance(cornerRadius: 13.5, shadowStrength: 0).hasShadow)
    }

    func testShadowExportAddsTransparentPadding() throws {
        let document = CaptureDocument(frame: try makeFrame(width: 40, height: 30))
        document.setAppearance(CaptureAppearance(cornerRadius: 8, hasShadow: true))

        let rendered = try ImageExporter().render(document)

        XCTAssertEqual(rendered.width, 88)
        XCTAssertEqual(rendered.height, 78)
        XCTAssertEqual(alpha(of: rendered, x: 0, y: 0), 0)
        XCTAssertEqual(alpha(of: rendered, x: 44, y: 39), 255)
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

    private func alpha(of image: CGImage, x: Int, y: Int) -> UInt8 {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.interpolationQuality = .none
        context.translateBy(x: -CGFloat(x), y: -CGFloat(y))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixel[3]
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
