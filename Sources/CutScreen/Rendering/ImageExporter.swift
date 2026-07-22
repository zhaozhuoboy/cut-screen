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
        let content = try renderContent(document)
        return try applyAppearance(to: content, document: document)
    }

    private func renderContent(_ document: CaptureDocument) throws -> CGImage {
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

        var obscuredImages: [MosaicRenderKey: CGImage] = [:]
        for annotation in document.annotations {
            guard case .mosaic(let mosaic) = annotation.kind else { continue }
            let key = MosaicRenderKey(effect: mosaic.effect, lineWidth: Int(annotation.style.lineWidth.rounded()))
            let obscured: CGImage?
            if let cached = obscuredImages[key] {
                obscured = cached
            } else {
                obscured = obscuredImage(
                    document.baseImage,
                    effect: mosaic.effect,
                    lineWidth: annotation.style.lineWidth
                )
                if let obscured { obscuredImages[key] = obscured }
            }
            guard let obscured else { continue }
            context.saveGState()
            AnnotationPainter.mosaicClipPath(for: annotation, in: context, transform: transform, scale: scaleX)
            drawBase(obscured, in: context, width: width, height: height)
            context.restoreGState()
        }

        let magnifierSource = context.makeImage() ?? document.baseImage
        for annotation in document.annotations {
            switch annotation.kind {
            case .mosaic:
                continue
            case .magnifier:
                drawMagnifier(
                    annotation,
                    source: magnifierSource,
                    in: context,
                    transform: transform,
                    scale: scaleX,
                    width: width,
                    height: height
                )
                AnnotationPainter.draw(annotation, in: context, transform: transform, scale: scaleX)
            default:
                AnnotationPainter.draw(annotation, in: context, transform: transform, scale: scaleX)
            }
        }

        guard let image = context.makeImage() else { throw ImageExportError.imageCreation }
        return image
    }

    func data(for document: CaptureDocument, format: ExportFormat) throws -> Data {
        let image = try render(document)
        let representation: NSBitmapImageRep
        let data: Data?
        switch format {
        case .png:
            representation = NSBitmapImageRep(cgImage: image)
            data = representation.representation(using: .png, properties: [:])
        case .jpeg:
            representation = NSBitmapImageRep(cgImage: try flattenedOnWhite(image))
            data = representation.representation(using: .jpeg, properties: [.compressionFactor: 0.92])
        }
        guard let data else { throw ImageExportError.encoding }
        return data
    }

    private func applyAppearance(to image: CGImage, document: CaptureDocument) throws -> CGImage {
        let appearance = document.appearance
        guard appearance.cornerRadius > 0 || appearance.hasShadow else { return image }

        let scale = CGFloat(image.width) / max(document.pointSize.width, 1)
        let cornerRadius = min(
            appearance.cornerRadius * scale,
            CGFloat(min(image.width, image.height)) / 2
        )
        let padding = appearance.hasShadow ? Int(ceil(appearance.shadowPadding * scale)) : 0
        let outputWidth = image.width + padding * 2
        let outputHeight = image.height + padding * 2
        guard let context = makeContext(width: outputWidth, height: outputHeight) else {
            throw ImageExportError.contextCreation
        }

        let contentRect = CGRect(
            x: padding,
            y: padding,
            width: image.width,
            height: image.height
        )
        let path = CGPath(
            roundedRect: contentRect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )

        if appearance.hasShadow {
            context.saveGState()
            context.setShadow(
                offset: CGSize(width: 0, height: appearance.shadowOffsetY * scale),
                blur: appearance.shadowBlurRadius * scale,
                color: NSColor.black.withAlphaComponent(appearance.shadowOpacity).cgColor
            )
            context.addPath(path)
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
            context.restoreGState()
        }

        context.saveGState()
        context.addPath(path)
        context.clip()
        context.draw(image, in: contentRect)
        context.restoreGState()

        guard let output = context.makeImage() else { throw ImageExportError.imageCreation }
        return output
    }

    private func flattenedOnWhite(_ image: CGImage) throws -> CGImage {
        guard let context = makeContext(width: image.width, height: image.height) else {
            throw ImageExportError.contextCreation
        }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let output = context.makeImage() else { throw ImageExportError.imageCreation }
        return output
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

    private func drawMagnifier(
        _ annotation: Annotation,
        source: CGImage,
        in context: CGContext,
        transform: AnnotationPainter.PointTransform,
        scale: CGFloat,
        width: Int,
        height: Int
    ) {
        guard case .magnifier(let rect, let zoom) = annotation.kind else { return }
        let lens = AnnotationPainter.transformed(rect, transform: transform)
        guard lens.width > 1, lens.height > 1 else { return }

        context.saveGState()
        context.addEllipse(in: lens)
        context.clip()
        context.translateBy(x: lens.midX, y: lens.midY)
        context.scaleBy(x: max(1, zoom), y: max(1, zoom))
        context.translateBy(x: -lens.midX, y: -lens.midY)
        drawBase(source, in: context, width: width, height: height)
        context.restoreGState()
    }

    private func obscuredImage(_ image: CGImage, effect: MosaicEffect, lineWidth: CGFloat) -> CGImage? {
        let input = CIImage(cgImage: image)
        let multiplier: CGFloat = lineWidth <= 2 ? 0.8 : (lineWidth >= 8 ? 1.8 : 1.2)
        let baseAmount = max(6, min(input.extent.width, input.extent.height) / 120)
        let output: CIImage?
        switch effect {
        case .pixelate:
            output = CIFilter(
                name: "CIPixellate",
                parameters: [kCIInputImageKey: input, kCIInputScaleKey: baseAmount * multiplier]
            )?.outputImage?.cropped(to: input.extent)
        case .blur:
            output = CIFilter(
                name: "CIGaussianBlur",
                parameters: [
                    kCIInputImageKey: input.clampedToExtent(),
                    kCIInputRadiusKey: baseAmount * multiplier
                ]
            )?.outputImage?.cropped(to: input.extent)
        }
        guard let output else { return nil }
        return ciContext.createCGImage(output, from: input.extent)
    }

    private func drawBase(_ image: CGImage, in context: CGContext, width: Int, height: Int) {
        context.saveGState()
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.restoreGState()
    }
}

private struct MosaicRenderKey: Hashable {
    let effect: MosaicEffect
    let lineWidth: Int
}
