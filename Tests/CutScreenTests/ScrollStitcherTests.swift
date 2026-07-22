import XCTest
@testable import CutScreen

final class ScrollStitcherTests: XCTestCase {
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
}
