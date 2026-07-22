@preconcurrency import AppKit
@preconcurrency import ScreenCaptureKit
import CoreImage
import CoreMedia
import CoreVideo
import OSLog

final class ScrollCaptureSession: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let selection: Selection
    private let scale: CGFloat
    private let processingQueue = DispatchQueue(label: "com.cutscreen.scroll-capture", qos: .userInitiated)
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let stitcher: any ScrollStitching
    private let previewComposer = ScrollPreviewComposer()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CutScreen", category: "ScrollCapture")
    private var stream: SCStream?
    private var stopped = false
    private var receivedFrameCount = 0
    private var appendedFrameCount = 0
    private var noMatchCount = 0

    var onProgress: (@MainActor (StitchAppendResult, Int, CGImage?) -> Void)?
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
        // Trackpad scrolling can move hundreds of pixels between 12 fps samples.
        // A 30 fps stream keeps enough overlap for stitching while the queue stays
        // small enough to avoid retaining a large set of full-resolution frames.
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 2
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.colorSpaceName = CGColorSpace.sRGB

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: processingQueue)
        self.stream = stream
        try await stream.startCapture()
        logger.info(
            "Scroll stream started: \(configuration.width)x\(configuration.height), source=\(String(describing: configuration.sourceRect), privacy: .public)"
        )
    }

    func stop() async throws -> CGImage {
        guard !stopped else { return try stitcher.finalize() }
        stopped = true
        if let stream { try await stream.stopCapture() }
        await withCheckedContinuation { continuation in
            processingQueue.async { continuation.resume() }
        }
        let image = try stitcher.finalize()
        logger.info(
            "Scroll stream finished: received=\(self.receivedFrameCount), appended=\(self.appendedFrameCount), noMatch=\(self.noMatchCount), height=\(image.height)"
        )
        return image
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
        receivedFrameCount += 1
        let result = stitcher.append(image)
        switch result {
        case .appended:
            appendedFrameCount += 1
        case .noMatch:
            noMatchCount += 1
            if noMatchCount == 1 || noMatchCount.isMultiple(of: 15) {
                logger.warning(
                    "Unable to match scroll frame: received=\(self.receivedFrameCount), totalHeight=\(self.stitcher.totalPixelHeight)"
                )
            }
        default:
            break
        }
        let totalHeight = stitcher.totalPixelHeight
        let preview = previewComposer.update(frame: image, result: result)
        Task { @MainActor [weak self] in self?.onProgress?(result, totalHeight, preview) }
    }
}
