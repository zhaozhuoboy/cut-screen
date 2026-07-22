@preconcurrency import AppKit
@preconcurrency import ScreenCaptureKit
import CoreImage
import CoreMedia
import CoreVideo

final class ScrollCaptureSession: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let selection: Selection
    private let scale: CGFloat
    private let processingQueue = DispatchQueue(label: "com.cutscreen.scroll-capture", qos: .userInitiated)
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let stitcher: any ScrollStitching
    private var stream: SCStream?
    private var stopped = false

    var onProgress: (@MainActor (StitchAppendResult, Int) -> Void)?
    var onFailure: (@MainActor (any Error) -> Void)?

    init(selection: Selection, scale: CGFloat, stitcher: any ScrollStitching = IncrementalScrollStitcher()) {
        self.selection = selection
        self.scale = scale
        self.stitcher = stitcher
    }

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == selection.displayID }) else {
            throw ScreenCaptureError.displayUnavailable
        }
        let ownID = Bundle.main.bundleIdentifier
        let excluded = content.applications.filter {
            $0.bundleIdentifier == ownID || $0.processID == ProcessInfo.processInfo.processIdentifier
        }
        let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = CGRect(
            x: selection.localRect.minX,
            y: selection.screenFrame.height - selection.localRect.maxY,
            width: selection.localRect.width,
            height: selection.localRect.height
        )
        configuration.width = max(1, Int(selection.localRect.width * scale))
        configuration.height = max(1, Int(selection.localRect.height * scale))
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 8)
        configuration.queueDepth = 1
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.colorSpaceName = CGColorSpace.sRGB

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: processingQueue)
        self.stream = stream
        try await stream.startCapture()
    }

    func stop() async throws -> CGImage {
        guard !stopped else { return try stitcher.finalize() }
        stopped = true
        if let stream { try await stream.stopCapture() }
        await withCheckedContinuation { continuation in
            processingQueue.async { continuation.resume() }
        }
        return try stitcher.finalize()
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        guard !stopped else { return }
        stopped = true
        Task { @MainActor [weak self] in self?.onFailure?(error) }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard !stopped,
              type == .screen,
              sampleBuffer.isValid,
              let imageBuffer = sampleBuffer.imageBuffer else { return }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let statusValue = attachments.first?[.status] as? Int,
           SCFrameStatus(rawValue: statusValue) != .complete {
            return
        }

        let input = CIImage(cvPixelBuffer: imageBuffer)
        guard let image = ciContext.createCGImage(input, from: input.extent) else { return }
        let result = stitcher.append(image)
        let totalHeight = stitcher.totalPixelHeight
        Task { @MainActor [weak self] in self?.onProgress?(result, totalHeight) }
    }
}
