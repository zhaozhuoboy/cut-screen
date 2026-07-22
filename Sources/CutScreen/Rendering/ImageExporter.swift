import AppKit
import CoreImage
import UniformTypeIdentifiers

protocol AnnotationRendering {
    @MainActor func render(_ document: CaptureDocument) throws -> CGImage
}

protocol ImageExporting {
    @MainActor func data(for document: CaptureDocument, format: ExportFormat) throws -> Data
}

protocol ScreenshotExporting: AnnotationRendering, ImageExporting {}

enum ImageExportError: LocalizedError {
    case contextCreation
    case imageCreation
    case encoding

    var errorDescription: String? {
        switch self {
        case .contextCreation: return "无法创建图片绘制上下文。"
        case .imageCreation: return "无法生成图片。"
        case .encoding: return "无法编码图片。"
        }
    }
}

@MainActor
final class ImageExporter: ScreenshotExporting {
    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    func render(_ document: CaptureDocument) throws -> CGImage {
        guard !document.annotations.isEmpty else { return document.baseImage }
        let width = document.baseImage.width
        let height = document.baseImage.height
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw ImageExportError.contextCreation }

        drawBase(document.baseImage, in: context, width: width, height: height)
        let scaleX = CGFloat(width) / document.pointSize.width
        let scaleY = CGFloat(height) / document.pointSize.height
        let transform: AnnotationPainter.PointTransform = { point in
            CGPoint(x: point.x * scaleX, y: point.y * scaleY)
        }

        if document.annotations.contains(where: { if case .mosaic = $0.kind { return true }; return false }),
           let pixelated = pixelatedImage(document.baseImage) {
            for annotation in document.annotations {
                guard case .mosaic = annotation.kind else { continue }
                context.saveGState()
                AnnotationPainter.mosaicClipPath(for: annotation, in: context, transform: transform, scale: scaleX)
                drawBase(pixelated, in: context, width: width, height: height)
                context.restoreGState()
            }
        }

        for annotation in document.annotations {
            guard case .mosaic = annotation.kind else {
                AnnotationPainter.draw(annotation, in: context, transform: transform, scale: scaleX)
                continue
            }
        }

        guard let image = context.makeImage() else { throw ImageExportError.imageCreation }
        return image
    }

    func data(for document: CaptureDocument, format: ExportFormat) throws -> Data {
        let image = try render(document)
        let representation = NSBitmapImageRep(cgImage: image)
        let data: Data?
        switch format {
        case .png:
            data = representation.representation(using: .png, properties: [:])
        case .jpeg:
            data = representation.representation(using: .jpeg, properties: [.compressionFactor: 0.92])
        }
        guard let data else { throw ImageExportError.encoding }
        return data
    }

    private func pixelatedImage(_ image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        let scale = max(8, min(input.extent.width, input.extent.height) / 120)
        guard let output = CIFilter(
            name: "CIPixellate",
            parameters: [kCIInputImageKey: input, kCIInputScaleKey: scale]
        )?.outputImage else { return nil }
        return ciContext.createCGImage(output, from: input.extent)
    }

    private func drawBase(_ image: CGImage, in context: CGContext, width: Int, height: Int) {
        context.saveGState()
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.restoreGState()
    }
}
