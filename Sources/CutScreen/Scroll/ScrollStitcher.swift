import AppKit

enum StitchAppendResult: Equatable {
    case firstFrame
    case duplicate
    case appended(pixelHeight: Int, confidence: Double)
    case noMatch
    case limitReached
}

protocol ScrollStitching: AnyObject {
    var totalPixelHeight: Int { get }
    var fixedBottomPixelHeight: Int { get }
    var latestAppendedSourceRect: CGRect? { get }
    func append(_ image: CGImage) -> StitchAppendResult
    func finalize() throws -> CGImage
}

/// Builds a lightweight, downsampled copy of the accumulated long screenshot
/// for the live HUD. The full-resolution document remains disk-backed in the
/// stitcher, so showing progress does not duplicate the entire capture in RAM.
final class ScrollPreviewComposer {
    private let maximumWidth: Int
    private var strips: [CGImage] = []
    private var appliedBottomInset = 0
    private(set) var image: CGImage?

    init(maximumWidth: Int = 220) {
        self.maximumWidth = max(1, maximumWidth)
    }

    func update(
        frame: CGImage,
        result: StitchAppendResult,
        appendedSourceRect: CGRect? = nil,
        fixedBottomPixelHeight: Int = 0
    ) -> CGImage? {
        trimInitialFooterIfNeeded(
            sourceWidth: frame.width,
            fixedBottomPixelHeight: fixedBottomPixelHeight
        )
        let source: CGImage?
        switch result {
        case .firstFrame:
            strips.removeAll(keepingCapacity: true)
            appliedBottomInset = 0
            source = frame
        case .appended(let pixelHeight, _):
            if let appendedSourceRect {
                source = frame.cropping(to: appendedSourceRect)
            } else {
                let height = min(max(1, pixelHeight), frame.height)
                source = frame.cropping(to: CGRect(
                    x: 0,
                    y: frame.height - height,
                    width: frame.width,
                    height: height
                ))
            }
        case .duplicate, .noMatch, .limitReached:
            return image
        }

        guard let source, let strip = downsample(source) else { return image }
        strips.append(strip)
        image = composeStrips()
        return image
    }

    private func trimInitialFooterIfNeeded(sourceWidth: Int, fixedBottomPixelHeight: Int) {
        guard fixedBottomPixelHeight > appliedBottomInset,
              let first = strips.first,
              sourceWidth > 0 else { return }
        let additionalPixels = fixedBottomPixelHeight - appliedBottomInset
        let scaledTrim = max(1, Int((CGFloat(additionalPixels) * CGFloat(first.width) / CGFloat(sourceWidth)).rounded()))
        let retainedHeight = first.height - scaledTrim
        guard retainedHeight > 0,
              let trimmed = first.cropping(to: CGRect(x: 0, y: 0, width: first.width, height: retainedHeight)) else {
            return
        }
        strips[0] = trimmed
        appliedBottomInset = fixedBottomPixelHeight
        image = composeStrips()
    }

    private func downsample(_ source: CGImage) -> CGImage? {
        let width = min(maximumWidth, source.width)
        let scale = CGFloat(width) / CGFloat(source.width)
        let height = max(1, Int((CGFloat(source.height) * scale).rounded()))
        guard let context = makeContext(width: width, height: height) else { return nil }
        context.interpolationQuality = .medium
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private func composeStrips() -> CGImage? {
        guard let width = strips.first?.width else { return nil }
        let height = strips.reduce(0) { $0 + $1.height }
        guard let context = makeContext(width: width, height: height) else { return nil }
        context.interpolationQuality = .medium

        var top = height
        for strip in strips {
            top -= strip.height
            context.draw(strip, in: CGRect(x: 0, y: top, width: strip.width, height: strip.height))
        }
        return context.makeImage()
    }

    private func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }
}

enum ScrollStitchError: LocalizedError {
    case noFrames
    case inconsistentWidth
    case imageCreation

    var errorDescription: String? {
        switch self {
        case .noFrames: return "没有可拼接的滚动截图。"
        case .inconsistentWidth: return "滚动过程中截图区域宽度发生变化。"
        case .imageCreation: return "无法生成长截图，请缩短截图长度后重试。"
        }
    }
}

final class IncrementalScrollStitcher: ScrollStitching, @unchecked Sendable {
    static let maximumHeight = 50_000
    static let maximumPixels = 150_000_000
    static let maximumConsecutiveNoMatches = 10

    private(set) var totalPixelHeight = 0
    private(set) var fixedBottomPixelHeight = 0
    private(set) var latestAppendedSourceRect: CGRect?
    private var previousImage: CGImage?
    private var previousGray: GrayFrame?
    private var latestFooterImage: CGImage?
    private var pixelWidth = 0
    private var sessionDirectory: URL?
    private var rawFileURL: URL?
    private var fileHandle: FileHandle?
    private var storageError: (any Error)?
    private var consecutiveNoMatchCount = 0
    private var acceptedAppendCount = 0

    deinit {
        try? fileHandle?.close()
        if let sessionDirectory { try? FileManager.default.removeItem(at: sessionDirectory) }
    }

    func append(_ image: CGImage) -> StitchAppendResult {
        guard let previousImage, let previousGray else {
            do {
                try prepareStore(width: image.width)
                try appendPixels(from: image)
            } catch {
                storageError = error
                return .noMatch
            }
            self.previousImage = image
            self.previousGray = GrayFrame(image: image)
            pixelWidth = image.width
            totalPixelHeight = image.height
            latestAppendedSourceRect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            return .firstFrame
        }
        guard image.width == previousImage.width else { return .noMatch }

        let currentGray = GrayFrame(image: image)
        let stationaryDifference = GrayFrameMatcher.meanDifference(previousGray, currentGray, shift: 0)
        if stationaryDifference < 1.2 {
            consecutiveNoMatchCount = 0
            latestAppendedSourceRect = nil
            return .duplicate
        }

        if fixedBottomPixelHeight == 0, acceptedAppendCount == 0 {
            let previousEdgeGray = GrayFrame(
                image: previousImage,
                targetWidth: 96,
                maximumHeight: min(720, previousImage.height)
            )
            let currentEdgeGray = GrayFrame(
                image: image,
                targetWidth: 96,
                maximumHeight: min(720, image.height)
            )
            let grayInset = GrayFrameMatcher.stationaryBottomInset(
                previous: previousEdgeGray,
                current: currentEdgeGray
            )
            let detectedInset = Int(
                (Double(grayInset) / Double(max(1, currentEdgeGray.height)) * Double(image.height)).rounded()
            )
            if detectedInset >= 12, detectedInset <= image.height / 4 {
                do {
                    try removeStoredBottom(pixelHeight: detectedInset)
                    fixedBottomPixelHeight = detectedInset
                } catch {
                    storageError = error
                    return .noMatch
                }
            }
        }
        updateLatestFooter(from: image)

        // Once the live viewport has moved too far away from the last accepted
        // frame, later repeated page sections can look like a valid overlap with
        // that stale frame. Stop accepting new strips until the user returns to
        // the last valid viewport instead of corrupting the long screenshot.
        guard consecutiveNoMatchCount < Self.maximumConsecutiveNoMatches else {
            latestAppendedSourceRect = nil
            return .noMatch
        }

        guard let match = GrayFrameMatcher.bestVerticalShift(previous: previousGray, current: currentGray),
              match.difference <= 20,
              match.confidence >= 0.66,
              stationaryDifference - match.difference >= max(0.75, stationaryDifference * 0.08) else {
            consecutiveNoMatchCount += 1
            latestAppendedSourceRect = nil
            return .noMatch
        }

        let pixelShift = max(1, Int((Double(match.shift) / Double(currentGray.height)) * Double(image.height)))
        let proposedHeight = totalPixelHeight + pixelShift
        let finalHeight = proposedHeight + fixedBottomPixelHeight
        guard finalHeight <= Self.maximumHeight,
              finalHeight * image.width <= Self.maximumPixels else {
            latestAppendedSourceRect = nil
            return .limitReached
        }

        let scrollingBottom = image.height - fixedBottomPixelHeight
        guard pixelShift <= scrollingBottom else {
            latestAppendedSourceRect = nil
            return .noMatch
        }
        let cropRect = CGRect(
            x: 0,
            y: scrollingBottom - pixelShift,
            width: image.width,
            height: pixelShift
        )
        guard let strip = image.cropping(to: cropRect) else { return .noMatch }
        do {
            try appendPixels(from: strip)
        } catch {
            storageError = error
            return .noMatch
        }
        totalPixelHeight = proposedHeight
        self.previousImage = image
        self.previousGray = currentGray
        consecutiveNoMatchCount = 0
        acceptedAppendCount += 1
        latestAppendedSourceRect = cropRect
        return .appended(pixelHeight: pixelShift, confidence: match.confidence)
    }

    func finalize() throws -> CGImage {
        if let storageError { throw storageError }
        guard totalPixelHeight > 0, pixelWidth > 0, let rawFileURL else { throw ScrollStitchError.noFrames }
        if let latestFooterImage, fixedBottomPixelHeight > 0 {
            try appendPixels(from: latestFooterImage)
            totalPixelHeight += latestFooterImage.height
            self.latestFooterImage = nil
        }
        try fileHandle?.close()
        fileHandle = nil

        let mappedData = try Data(contentsOf: rawFileURL, options: [.mappedIfSafe])
        guard let provider = CGDataProvider(data: mappedData as CFData),
              let image = CGImage(
                width: pixelWidth,
                height: totalPixelHeight,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: pixelWidth * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue).union(.byteOrder32Big),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else { throw ScrollStitchError.imageCreation }
        try? FileManager.default.removeItem(at: rawFileURL)
        return image
    }

    private func prepareStore(width: Int) throws {
        let directory = try TemporaryFileStore.createSessionDirectory()
        let fileURL = directory.appendingPathComponent("scroll.rgba")
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        sessionDirectory = directory
        rawFileURL = fileURL
        fileHandle = try FileHandle(forWritingTo: fileURL)
        pixelWidth = width
    }

    private func appendPixels(from image: CGImage) throws {
        guard image.width == pixelWidth, let fileHandle else { throw ScrollStitchError.inconsistentWidth }
        let bytesPerRow = image.width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * image.height)
        guard let context = CGContext(
            data: &bytes,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue).union(.byteOrder32Big).rawValue
        ) else { throw ScrollStitchError.imageCreation }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        try fileHandle.write(contentsOf: Data(bytes))
    }

    private func removeStoredBottom(pixelHeight: Int) throws {
        guard pixelHeight > 0,
              pixelHeight < totalPixelHeight,
              let fileHandle,
              let previousImage,
              let retained = previousImage.cropping(to: CGRect(
                x: 0,
                y: 0,
                width: previousImage.width,
                height: previousImage.height - pixelHeight
              )) else { return }
        try fileHandle.truncate(atOffset: 0)
        try fileHandle.seek(toOffset: 0)
        totalPixelHeight = 0
        try appendPixels(from: retained)
        totalPixelHeight = retained.height
    }

    private func updateLatestFooter(from image: CGImage) {
        guard fixedBottomPixelHeight > 0 else { return }
        latestFooterImage = image.cropping(to: CGRect(
            x: 0,
            y: image.height - fixedBottomPixelHeight,
            width: image.width,
            height: fixedBottomPixelHeight
        ))
    }
}

struct GrayFrame: Equatable, Sendable {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    init(image: CGImage, targetWidth: Int = 96, maximumHeight: Int = 360) {
        let width = min(targetWidth, image.width)
        // Keep substantially more vertical detail than horizontal detail. Scroll
        // matching depends on accurate row displacement, not image aspect ratio.
        let height = min(maximumHeight, image.height)
        var pixels = [UInt8](repeating: 0, count: width * height)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        self.init(width: width, height: height, pixels: pixels)
    }
}

enum GrayFrameMatcher {
    struct Match: Equatable, Sendable {
        let shift: Int
        let confidence: Double
        let difference: Double
    }

    static func bestVerticalShift(previous: GrayFrame, current: GrayFrame) -> Match? {
        guard previous.width == current.width,
              previous.height == current.height,
              previous.height >= 12 else { return nil }

        // Smooth wheel and trackpad scrolling often advances only one or two
        // downsampled rows between sampled frames. Starting at a larger shift
        // over-appends overlapping content and visibly repeats the first frame.
        let minimumShift = 1
        // Discrete mouse wheels and fast trackpad flicks can jump farther than
        // smooth scrolling. Keep enough headroom while still rejecting
        // repeated page sections matched against a stale frame.
        let maximumShift = max(minimumShift, Int(Double(previous.height) * 0.50))
        var candidates: [(shift: Int, difference: Double)] = []

        for shift in minimumShift...maximumShift {
            let difference = meanDifference(previous, current, shift: shift)
            candidates.append((shift, difference))
        }

        guard let minimumDifference = candidates.map(\.difference).min() else { return nil }
        let nearBestTolerance = max(0.65, minimumDifference * 0.05)
        guard let best = candidates.first(where: { $0.difference <= minimumDifference + nearBestTolerance }) else {
            return nil
        }

        let separationDistance = max(2, previous.height / 50)
        let secondBest = candidates
            .filter { abs($0.shift - best.shift) > separationDistance }
            .map(\.difference)
            .min() ?? 255
        let similarity = max(0, 1 - best.difference / 48)
        let uniqueness = min(1, max(0, (secondBest - best.difference) / 8))
        let confidence = similarity * 0.82 + uniqueness * 0.18
        return Match(shift: best.shift, confidence: confidence, difference: best.difference)
    }

    static func stationaryBottomInset(previous: GrayFrame, current: GrayFrame) -> Int {
        guard previous.width == current.width,
              previous.height == current.height,
              previous.width >= 8,
              previous.height >= 40 else { return 0 }

        let maximumRows = max(1, previous.height / 4)
        let minimumRows = max(10, previous.height / 36)
        let startColumn = previous.width / 20
        let endColumn = max(startColumn + 1, previous.width - previous.width / 12)
        var stableRows = 0

        for row in stride(
            from: previous.height - 1,
            through: previous.height - maximumRows,
            by: -1
        ) {
            var squaredTotal: Int64 = 0
            var count: Int64 = 0
            let offset = row * previous.width
            for column in startColumn..<endColumn {
                let difference = Int64(
                    Int(previous.pixels[offset + column]) - Int(current.pixels[offset + column])
                )
                squaredTotal += difference * difference
                count += 1
            }
            let rowDifference = count > 0 ? sqrt(Double(squaredTotal) / Double(count)) : 255
            guard rowDifference <= 2.2 else { break }
            stableRows += 1
        }

        return stableRows >= minimumRows ? stableRows : 0
    }

    static func meanDifference(_ previous: GrayFrame, _ current: GrayFrame, shift: Int) -> Double {
        guard previous.width == current.width, previous.height == current.height else { return 255 }
        let overlap = previous.height - shift
        guard overlap > 4 else { return 255 }

        // Ignore common sticky headers/footers and page sidebars. RMS difference
        // keeps sparse text edges meaningful on otherwise white pages.
        let startRow = min(max(0, min(current.height / 4, overlap / 3)), overlap - 1)
        let endRow = max(startRow + 1, overlap - max(1, min(current.height / 8, overlap / 5)))
        let startColumn = current.width / 10
        let endColumn = max(startColumn + 1, current.width - current.width / 10)
        var squaredTotal: Int64 = 0
        var count: Int64 = 0
        for row in startRow..<endRow {
            let previousOffset = (row + shift) * previous.width
            let currentOffset = row * current.width
            for column in stride(from: startColumn, to: endColumn, by: 2) {
                let difference = Int64(
                    Int(previous.pixels[previousOffset + column])
                        - Int(current.pixels[currentOffset + column])
                )
                squaredTotal += difference * difference
                count += 1
            }
        }
        return count > 0 ? sqrt(Double(squaredTotal) / Double(count)) : 255
    }
}
