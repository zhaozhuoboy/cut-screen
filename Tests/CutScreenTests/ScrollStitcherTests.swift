import XCTest
@testable import CutScreen

final class ScrollStitcherTests: XCTestCase {
    func testScrollOverlayLeavesTheCaptureSelectionUncovered() {
        let displayBounds = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let selection = CGRect(x: 180, y: 140, width: 760, height: 500)
        let masks = ScrollOverlayGeometry.maskRects(
            in: displayBounds,
            outside: selection
        )

        XCTAssertEqual(masks.count, 4)
        XCTAssertTrue(masks.allSatisfy { $0.intersection(selection).isEmpty })
        XCTAssertEqual(
            masks.reduce(CGFloat.zero) { $0 + $1.width * $1.height },
            displayBounds.width * displayBounds.height - selection.width * selection.height
        )
    }

    func testScrollBorderUsesFourThinWindowsOutsideTheSelection() {
        let screenBounds = CGRect(x: -200, y: 40, width: 1200, height: 800)
        let selection = CGRect(x: 50, y: 180, width: 600, height: 420)
        let borders = ScrollOverlayGeometry.borderRects(
            around: selection,
            in: screenBounds
        )

        XCTAssertEqual(borders.count, 4)
        XCTAssertTrue(borders.allSatisfy { $0.intersection(selection).isEmpty })
        XCTAssertTrue(borders.allSatisfy { screenBounds.contains($0) })
    }

    func testFindsKnownVerticalShift() {
        let width = 12
        let height = 40
        let source = (0..<(width * 55)).map { UInt8(($0 * 37) % 251) }
        let first = GrayFrame(width: width, height: height, pixels: Array(source[0..<(width * height)]))
        let shift = 9
        let second = GrayFrame(
            width: width,
            height: height,
            pixels: Array(source[(shift * width)..<((shift + height) * width)])
        )

        let match = GrayFrameMatcher.bestVerticalShift(previous: first, current: second)
        XCTAssertEqual(match?.shift, shift)
        XCTAssertGreaterThan(match?.confidence ?? 0, 0.80)
        XCTAssertLessThan(match?.difference ?? 255, 1)
    }

    func testRejectsMismatchedDimensions() {
        let first = GrayFrame(width: 4, height: 20, pixels: [UInt8](repeating: 0, count: 80))
        let second = GrayFrame(width: 5, height: 20, pixels: [UInt8](repeating: 0, count: 100))
        XCTAssertNil(GrayFrameMatcher.bestVerticalShift(previous: first, current: second))
    }

    func testIdenticalFramesHaveZeroDifference() {
        let frame = GrayFrame(width: 8, height: 20, pixels: [UInt8](repeating: 90, count: 160))
        XCTAssertEqual(GrayFrameMatcher.meanDifference(frame, frame, shift: 0), 0)
    }

    func testFinalImageUsesDiskBackedStripsAndExpectedHeight() throws {
        let width = 24
        let viewportHeight = 48
        let shift = 11
        let first = makeImage(width: width, height: viewportHeight, rowOffset: 0)
        let second = makeImage(width: width, height: viewportHeight, rowOffset: shift)
        let stitcher = IncrementalScrollStitcher()

        XCTAssertEqual(stitcher.append(first), .firstFrame)
        let firstGray = GrayFrame(image: first)
        let secondGray = GrayFrame(image: second)
        let directMatch = GrayFrameMatcher.bestVerticalShift(previous: firstGray, current: secondGray)
        let expectedDifference = GrayFrameMatcher.meanDifference(firstGray, secondGray, shift: shift)
        let appendResult = stitcher.append(second)
        guard case .appended(let added, _) = appendResult else {
            return XCTFail("Second frame should append, got \(appendResult), match: \(String(describing: directMatch)), expected diff: \(expectedDifference)")
        }
        XCTAssertLessThanOrEqual(abs(added - shift), 1)
        let result = try stitcher.finalize()
        XCTAssertEqual(result.width, width)
        XCTAssertEqual(result.height, viewportHeight + added)
        let expected = makeImage(width: width, height: viewportHeight + added, rowOffset: 0)
        let resultGray = GrayFrame(image: result, targetWidth: width, maximumHeight: result.height)
        let expectedGray = GrayFrame(image: expected, targetWidth: width, maximumHeight: expected.height)
        XCTAssertLessThan(GrayFrameMatcher.meanDifference(expectedGray, resultGray, shift: 0), 2)
    }

    func testMatchesTextPageWithFixedHeaderAndSidebar() {
        let width = 240
        let height = 300
        let pixelShift = 64
        let first = makeTextPageViewport(width: width, height: height, rowOffset: 0)
        let second = makeTextPageViewport(width: width, height: height, rowOffset: pixelShift)
        let firstGray = GrayFrame(image: first)
        let secondGray = GrayFrame(image: second)

        let match = GrayFrameMatcher.bestVerticalShift(previous: firstGray, current: secondGray)
        let expected = Int(Double(pixelShift) * Double(firstGray.height) / Double(height))

        XCTAssertNotNil(match)
        XCTAssertLessThanOrEqual(abs((match?.shift ?? 0) - expected), 2)
        XCTAssertLessThan(match?.difference ?? 255, 20)

        let stitcher = IncrementalScrollStitcher()
        XCTAssertEqual(stitcher.append(first), .firstFrame)
        guard case .appended(let added, _) = stitcher.append(second) else {
            return XCTFail("Text page frame should append")
        }
        XCTAssertLessThanOrEqual(abs(added - pixelShift), 4)
    }

    func testRejectsFrameWithoutVerticalOverlap() {
        let first = makeTextPageViewport(width: 240, height: 300, rowOffset: 0)
        let unrelated = makeTextPageViewport(width: 240, height: 300, rowOffset: 420)
        let stitcher = IncrementalScrollStitcher()

        XCTAssertEqual(stitcher.append(first), .firstFrame)
        XCTAssertEqual(stitcher.append(unrelated), .noMatch)
    }

    func testAppendsTextPageAtDifferentScrollSpeeds() {
        let width = 240
        let height = 300
        let offsets = [0, 18, 72, 150]
        let stitcher = IncrementalScrollStitcher()

        XCTAssertEqual(
            stitcher.append(makeTextPageViewport(width: width, height: height, rowOffset: offsets[0])),
            .firstFrame
        )
        for (previous, current) in zip(offsets, offsets.dropFirst()) {
            let result = stitcher.append(makeTextPageViewport(width: width, height: height, rowOffset: current))
            guard case .appended(let added, _) = result else {
                return XCTFail("Frame at offset \(current) should append, got \(result)")
            }
            XCTAssertLessThanOrEqual(abs(added - (current - previous)), 2)
        }

        XCTAssertLessThanOrEqual(abs(stitcher.totalPixelHeight - (height + offsets.last!)), 4)
    }

    func testTinySmoothScrollDoesNotRepeatOverlappingContent() {
        let width = 240
        let height = 600
        let offsets = [0, 2, 4, 7, 10]
        let stitcher = IncrementalScrollStitcher()

        XCTAssertEqual(
            stitcher.append(makeTextPageViewport(width: width, height: height, rowOffset: offsets[0])),
            .firstFrame
        )
        for current in offsets.dropFirst() {
            let result = stitcher.append(makeTextPageViewport(width: width, height: height, rowOffset: current))
            guard case .appended = result else {
                return XCTFail("Tiny scroll at offset \(current) should append once, got \(result)")
            }
        }

        XCTAssertLessThanOrEqual(abs(stitcher.totalPixelHeight - (height + offsets.last!)), 4)
    }

    func testDetectsStationarySpreadsheetFooter() {
        let width = 360
        let height = 420
        let footerHeight = 44
        let first = GrayFrame(image: makeSpreadsheetViewport(
            width: width,
            height: height,
            rowOffset: 0,
            footerHeight: footerHeight
        ))
        let second = GrayFrame(image: makeSpreadsheetViewport(
            width: width,
            height: height,
            rowOffset: 18,
            footerHeight: footerHeight
        ))

        let inset = GrayFrameMatcher.stationaryBottomInset(previous: first, current: second)
        let expected = Int((Double(footerHeight) * Double(first.height) / Double(height)).rounded())
        XCTAssertLessThanOrEqual(abs(inset - expected), 3)
    }

    func testTrackpadSpreadsheetFramesKeepFixedFooterOnlyOnce() throws {
        let width = 360
        let height = 420
        let footerHeight = 44
        let offsets = [0, 3, 8, 16, 29, 47, 70]
        let stitcher = IncrementalScrollStitcher()

        XCTAssertEqual(
            stitcher.append(makeSpreadsheetViewport(
                width: width,
                height: height,
                rowOffset: offsets[0],
                footerHeight: footerHeight
            )),
            .firstFrame
        )
        var appendedCount = 0
        for current in offsets.dropFirst() {
            let result = stitcher.append(makeSpreadsheetViewport(
                width: width,
                height: height,
                rowOffset: current,
                footerHeight: footerHeight
            ))
            switch result {
            case .appended:
                appendedCount += 1
            case .duplicate, .noMatch:
                // Sub-pixel/tiny movements are intentionally held until a
                // later trackpad frame has accumulated enough displacement.
                continue
            default:
                return XCTFail("Unexpected trackpad result at offset \(current): \(result)")
            }
        }

        XCTAssertGreaterThan(appendedCount, 0)
        XCTAssertLessThanOrEqual(abs(stitcher.fixedBottomPixelHeight - footerHeight), 6)
        let result = try stitcher.finalize()
        XCTAssertLessThanOrEqual(abs(result.height - (height + offsets.last!)), 5)

        let expected = makeSpreadsheetLongImage(
            width: width,
            viewportHeight: height,
            extraRows: offsets.last!,
            footerHeight: footerHeight
        )
        let comparisonHeight = min(result.height, expected.height)
        let resultComparison = try XCTUnwrap(result.cropping(to: CGRect(
            x: 0,
            y: 0,
            width: result.width,
            height: comparisonHeight
        )))
        let expectedComparison = try XCTUnwrap(expected.cropping(to: CGRect(
            x: 0,
            y: 0,
            width: expected.width,
            height: comparisonHeight
        )))
        let resultGray = GrayFrame(image: resultComparison, targetWidth: 96, maximumHeight: comparisonHeight)
        let expectedGray = GrayFrame(image: expectedComparison, targetWidth: 96, maximumHeight: comparisonHeight)
        XCTAssertLessThan(GrayFrameMatcher.meanDifference(expectedGray, resultGray, shift: 0), 25)
    }

    func testLivePreviewTrimsFixedFooterBeforeAppendingTrackpadStrip() throws {
        let width = 360
        let height = 420
        let footerHeight = 44
        let shift = 20
        let first = makeSpreadsheetViewport(
            width: width,
            height: height,
            rowOffset: 0,
            footerHeight: footerHeight
        )
        let second = makeSpreadsheetViewport(
            width: width,
            height: height,
            rowOffset: shift,
            footerHeight: footerHeight
        )
        let composer = ScrollPreviewComposer(maximumWidth: 180)

        let initial = try XCTUnwrap(composer.update(frame: first, result: .firstFrame))
        XCTAssertEqual(initial.height, 210)

        let sourceRect = CGRect(
            x: 0,
            y: height - footerHeight - shift,
            width: width,
            height: shift
        )
        let preview = try XCTUnwrap(composer.update(
            frame: second,
            result: .appended(pixelHeight: shift, confidence: 0.9),
            appendedSourceRect: sourceRect,
            fixedBottomPixelHeight: footerHeight
        ))
        XCTAssertEqual(preview.height, 198)
    }

    func testDoesNotResumeAgainstStaleFrameAfterRepeatedMatchFailures() {
        let width = 240
        let height = 300
        let stitcher = IncrementalScrollStitcher()
        let first = makeTextPageViewport(width: width, height: height, rowOffset: 0)
        let unrelated = makeTextPageViewport(width: width, height: height, rowOffset: 420)

        XCTAssertEqual(stitcher.append(first), .firstFrame)
        for _ in 0..<IncrementalScrollStitcher.maximumConsecutiveNoMatches {
            XCTAssertEqual(stitcher.append(unrelated), .noMatch)
        }

        let staleButMatchable = makeTextPageViewport(width: width, height: height, rowOffset: 18)
        XCTAssertEqual(stitcher.append(staleButMatchable), .noMatch)
        XCTAssertEqual(stitcher.totalPixelHeight, height)
    }

    func testLivePreviewAddsOnlyNewlyStitchedStrip() throws {
        let first = makeImage(width: 100, height: 80, rowOffset: 0)
        let second = makeImage(width: 100, height: 80, rowOffset: 20)
        let composer = ScrollPreviewComposer(maximumWidth: 50)

        let initial = try XCTUnwrap(composer.update(frame: first, result: .firstFrame))
        XCTAssertEqual(initial.width, 50)
        XCTAssertEqual(initial.height, 40)

        let accumulated = try XCTUnwrap(composer.update(
            frame: second,
            result: .appended(pixelHeight: 20, confidence: 0.9)
        ))
        XCTAssertEqual(accumulated.width, 50)
        XCTAssertEqual(accumulated.height, 50)

        let duplicate = try XCTUnwrap(composer.update(frame: second, result: .duplicate))
        XCTAssertTrue(duplicate === accumulated)
    }

    private func makeImage(width: Int, height: Int, rowOffset: Int = 0) -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for row in 0..<height {
            for column in 0..<width {
                let offset = (row * width + column) * 4
                let sourceRow = row + rowOffset
                var hash = UInt32(sourceRow) &* 1_103_515_245 &+ UInt32(column) &* 12_345
                hash ^= hash >> 13
                hash &*= 2_654_435_761
                bytes[offset] = UInt8(truncatingIfNeeded: hash)
                bytes[offset + 1] = UInt8(truncatingIfNeeded: hash >> 8)
                bytes[offset + 2] = UInt8(truncatingIfNeeded: hash >> 16)
            }
        }
        let data = Data(bytes)
        let provider = CGDataProvider(data: data as CFData)!
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

    private func makeTextPageViewport(width: Int, height: Int, rowOffset: Int) -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        let headerHeight = max(20, height / 10)
        let sidebarWidth = max(18, width / 10)

        for row in 0..<height {
            for column in 0..<width {
                let offset = (row * width + column) * 4
                let pageRow = row + rowOffset
                let value: UInt8

                if row < headerHeight {
                    value = column < width / 3 ? 58 : 82
                } else if column >= width - sidebarWidth {
                    value = row % 34 < 3 ? 174 : 226
                } else {
                    let line = pageRow / 26
                    let rowInLine = pageRow % 26
                    var lineHash = UInt32(truncatingIfNeeded: line) &* 2_654_435_761
                    lineHash ^= lineHash >> 13
                    lineHash &*= 1_103_515_245
                    let lineRange = max(80, width - sidebarWidth - 80)
                    let lineEnd = 70 + Int(lineHash % UInt32(lineRange))
                    if (4...6).contains(rowInLine), column >= 24, column < lineEnd {
                        value = 38
                    } else if (11...18).contains(rowInLine), column >= 24, column < 46 {
                        value = UInt8(95 + Int(lineHash % 80))
                    } else {
                        value = 248
                    }
                }

                bytes[offset] = value
                bytes[offset + 1] = value
                bytes[offset + 2] = value
                bytes[offset + 3] = 255
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

    private func makeSpreadsheetViewport(
        width: Int,
        height: Int,
        rowOffset: Int,
        footerHeight: Int
    ) -> CGImage {
        makeSpreadsheetImage(
            width: width,
            height: height,
            headerHeight: 96,
            footerHeight: footerHeight,
            contentRowOffset: rowOffset
        )
    }

    private func makeSpreadsheetLongImage(
        width: Int,
        viewportHeight: Int,
        extraRows: Int,
        footerHeight: Int
    ) -> CGImage {
        makeSpreadsheetImage(
            width: width,
            height: viewportHeight + extraRows,
            headerHeight: 96,
            footerHeight: footerHeight,
            contentRowOffset: 0
        )
    }

    private func makeSpreadsheetImage(
        width: Int,
        height: Int,
        headerHeight: Int,
        footerHeight: Int,
        contentRowOffset: Int
    ) -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for row in 0..<height {
            for column in 0..<width {
                let offset = (row * width + column) * 4
                let value: UInt8
                if row < headerHeight {
                    value = row % 24 < 2 || column % 72 < 2 ? 176 : 232
                } else if row >= height - footerHeight {
                    let footerRow = row - (height - footerHeight)
                    if footerRow < 2 {
                        value = 156
                    } else if footerRow % 16 < 2 || column % 58 < 2 {
                        value = 188
                    } else {
                        value = 238
                    }
                } else if column >= width - 14 {
                    value = row % 30 < 8 ? 178 : 226
                } else {
                    let pageRow = row - headerHeight + contentRowOffset
                    let rowNumber = pageRow / 22
                    let rowInCell = pageRow % 22
                    var hash = UInt32(truncatingIfNeeded: rowNumber) &* 2_654_435_761
                    hash ^= hash >> 13
                    hash &*= 1_103_515_245
                    if rowInCell == 0 || column % 54 == 0 {
                        value = 202
                    } else if (6...9).contains(rowInCell),
                              column > 18,
                              column < 80 + Int(hash % UInt32(max(1, width - 110))) {
                        value = UInt8(52 + Int(hash % 80))
                    } else {
                        value = 248
                    }
                }
                bytes[offset] = value
                bytes[offset + 1] = value
                bytes[offset + 2] = value
                bytes[offset + 3] = 255
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
