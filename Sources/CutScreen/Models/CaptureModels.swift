import AppKit
import CoreGraphics

struct CapturedDisplay {
    let displayID: CGDirectDisplayID
    let screenFrame: CGRect
    let scale: CGFloat
    let image: CGImage
    let windows: [DetectedWindow]

    var pointSize: CGSize { screenFrame.size }

    func localCaptureRegion(at point: CGPoint) -> CGRect {
        let displayBounds = CGRect(origin: .zero, size: pointSize)
        for window in windows {
            let localWindow = window.frame
                .offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
                .intersection(displayBounds)
            if !localWindow.isNull, localWindow.contains(point) {
                return localWindow
            }
        }
        return displayBounds
    }

    func ownerProcessIdentifier(at point: CGPoint) -> pid_t? {
        let displayBounds = CGRect(origin: .zero, size: pointSize)
        guard displayBounds.contains(point) else { return nil }
        for window in windows {
            let localWindow = window.frame
                .offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
                .intersection(displayBounds)
            if !localWindow.isNull, localWindow.contains(point) {
                return window.ownerProcessIdentifier
            }
        }
        return nil
    }

    func pixelAlignedLocalRect(_ localRect: CGRect) -> CGRect {
        let clipped = localRect.standardized.intersection(CGRect(origin: .zero, size: pointSize))
        guard clipped.width > 0, clipped.height > 0, scale > 0 else { return .zero }
        let minimumX = floor(clipped.minX * scale) / scale
        let minimumY = floor(clipped.minY * scale) / scale
        let maximumX = ceil(clipped.maxX * scale) / scale
        let maximumY = ceil(clipped.maxY * scale) / scale
        return CGRect(
            x: minimumX,
            y: minimumY,
            width: maximumX - minimumX,
            height: maximumY - minimumY
        ).intersection(CGRect(origin: .zero, size: pointSize))
    }

    func crop(localRect: CGRect) -> CGImage? {
        let clipped = pixelAlignedLocalRect(localRect)
        guard clipped.width >= 1, clipped.height >= 1 else { return nil }

        let pixelRect = CGRect(
            x: (clipped.minX * scale).rounded(),
            y: ((pointSize.height - clipped.maxY) * scale).rounded(),
            width: (clipped.width * scale).rounded(),
            height: (clipped.height * scale).rounded()
        )
        return image.cropping(to: pixelRect)
    }

    func pixelColor(at localPoint: CGPoint) -> CapturedPixelColor? {
        guard scale > 0, image.width > 0, image.height > 0 else { return nil }
        let pixelX = min(max(0, Int(floor(localPoint.x * scale))), image.width - 1)
        let pixelYFromBottom = min(max(0, Int(floor(localPoint.y * scale))), image.height - 1)
        let imageY = image.height - 1 - pixelYFromBottom
        guard let pixelImage = image.cropping(to: CGRect(x: pixelX, y: imageY, width: 1, height: 1)) else {
            return nil
        }

        var rgba = [UInt8](repeating: 0, count: 4)
        let rendered = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let data = bytes.baseAddress,
                  let context = CGContext(
                    data: data,
                    width: 1,
                    height: 1,
                    bitsPerComponent: 8,
                    bytesPerRow: 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                        | CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return false }
            context.interpolationQuality = .none
            context.draw(pixelImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard rendered else { return nil }

        let alpha = Int(rgba[3])
        if alpha > 0, alpha < 255 {
            for index in 0...2 {
                rgba[index] = UInt8(min(255, Int(rgba[index]) * 255 / alpha))
            }
        }
        return CapturedPixelColor(red: rgba[0], green: rgba[1], blue: rgba[2])
    }
}

struct CapturedPixelColor: Equatable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    var hexString: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    var nsColor: NSColor {
        NSColor(
            srgbRed: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: 1
        )
    }
}

struct DetectedWindow: Equatable {
    let windowID: CGWindowID
    let ownerName: String
    let ownerProcessIdentifier: pid_t?
    let frame: CGRect
    let layer: Int

    init(
        windowID: CGWindowID,
        ownerName: String,
        ownerProcessIdentifier: pid_t? = nil,
        frame: CGRect,
        layer: Int
    ) {
        self.windowID = windowID
        self.ownerName = ownerName
        self.ownerProcessIdentifier = ownerProcessIdentifier
        self.frame = frame
        self.layer = layer
    }
}

struct Selection: Equatable {
    let displayID: CGDirectDisplayID
    let screenFrame: CGRect
    var localRect: CGRect

    var globalRect: CGRect {
        localRect.offsetBy(dx: screenFrame.minX, dy: screenFrame.minY)
    }
}

struct CapturedFrame {
    let image: CGImage
    let pointSize: CGSize
    let scale: CGFloat
}

enum ExportFormat: String, CaseIterable {
    case png
    case jpeg

    var fileExtension: String { rawValue == "jpeg" ? "jpg" : "png" }
}
