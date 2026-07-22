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
        XCTAssertGreaterThan(match?.confidence ?? 0, 0.85)
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
}
