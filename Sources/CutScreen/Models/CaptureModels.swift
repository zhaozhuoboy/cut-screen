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
