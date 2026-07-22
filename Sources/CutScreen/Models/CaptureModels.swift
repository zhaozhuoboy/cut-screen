import AppKit
import CoreGraphics

struct CapturedDisplay {
    let displayID: CGDirectDisplayID
    let screenFrame: CGRect
    let scale: CGFloat
    let image: CGImage
    let windows: [DetectedWindow]

    var pointSize: CGSize { screenFrame.size }

    func crop(localRect: CGRect) -> CGImage? {
        let clipped = localRect.standardized.intersection(CGRect(origin: .zero, size: pointSize))
        guard clipped.width >= 1, clipped.height >= 1 else { return nil }

        let pixelRect = CGRect(
            x: clipped.minX * scale,
            y: (pointSize.height - clipped.maxY) * scale,
            width: clipped.width * scale,
            height: clipped.height * scale
        ).integral
        return image.cropping(to: pixelRect)
    }
}

struct DetectedWindow: Equatable {
    let windowID: CGWindowID
    let ownerName: String
    let frame: CGRect
    let layer: Int
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
