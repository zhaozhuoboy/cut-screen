import CoreImage

enum MagnifierImageRenderer {
    static func render(
        source: CGImage,
        sourcePixelRect: CGRect,
        targetPixelSize: CGSize,
        context: CIContext
    ) -> CGImage? {
        guard let cropped = source.cropping(to: sourcePixelRect) else { return nil }
        let targetWidth = max(1, Int(targetPixelSize.width.rounded()))
        let targetHeight = max(1, Int(targetPixelSize.height.rounded()))
        let horizontalScale = CGFloat(targetWidth) / CGFloat(cropped.width)
        let verticalScale = CGFloat(targetHeight) / CGFloat(cropped.height)
        guard horizontalScale > 0, verticalScale > 0 else { return nil }

        let input = CIImage(cgImage: cropped)
        guard let scaled = CIFilter(
            name: "CILanczosScaleTransform",
            parameters: [
                kCIInputImageKey: input,
                kCIInputScaleKey: horizontalScale,
                kCIInputAspectRatioKey: verticalScale / horizontalScale
            ]
        )?.outputImage else { return nil }

        let sharpened = CIFilter(
            name: "CIUnsharpMask",
            parameters: [
                kCIInputImageKey: scaled,
                kCIInputRadiusKey: 0.75,
                kCIInputIntensityKey: 0.62
            ]
        )?.outputImage ?? scaled
        let enhanced = CIFilter(
            name: "CIColorControls",
            parameters: [
                kCIInputImageKey: sharpened,
                kCIInputContrastKey: 1.04,
                kCIInputSaturationKey: 1.02
            ]
        )?.outputImage ?? sharpened
        let outputRect = CGRect(
            x: enhanced.extent.minX,
            y: enhanced.extent.minY,
            width: CGFloat(targetWidth),
            height: CGFloat(targetHeight)
        )
        return context.createCGImage(enhanced, from: outputRect)
    }
}
