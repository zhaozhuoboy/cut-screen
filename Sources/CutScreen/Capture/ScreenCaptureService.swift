@preconcurrency import AppKit
@preconcurrency import ScreenCaptureKit
import CoreImage
import CoreMedia
import CoreVideo

@MainActor
protocol ScreenCaptureProviding {
    func hasPermission() -> Bool
    func requestPermission() -> Bool
    func captureDisplays() async throws -> [CapturedDisplay]
}

enum ScreenCaptureError: LocalizedError {
    case permissionDenied
    case noDisplays
    case displayUnavailable
    case invalidFrame

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "没有屏幕录制权限。"
        case .noDisplays: return "没有找到可用显示器。"
        case .displayUnavailable: return "显示器在截图过程中不可用。"
        case .invalidFrame: return "未能读取有效的屏幕画面。"
        }
    }
}

@MainActor
final class SystemScreenCaptureService: ScreenCaptureProviding {
    private let windowDetector: any WindowDetecting

    init(windowDetector: any WindowDetecting = SystemWindowDetector()) {
        self.windowDetector = windowDetector
    }

    func hasPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    func requestPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    func captureDisplays() async throws -> [CapturedDisplay] {
        guard hasPermission() else { throw ScreenCaptureError.permissionDenied }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard !content.displays.isEmpty else { throw ScreenCaptureError.noDisplays }

        let ownBundleIdentifier = Bundle.main.bundleIdentifier
        let excludedApplications = content.applications.filter {
            $0.bundleIdentifier == ownBundleIdentifier || $0.processID == ProcessInfo.processInfo.processIdentifier
        }
        let detectedWindows = windowDetector.windows()
        var captures: [CapturedDisplay] = []

        for display in content.displays {
            guard let screen = Self.screen(for: display.displayID) else { continue }
            let filter = SCContentFilter(
                display: display,
                excludingApplications: excludedApplications,
                exceptingWindows: []
            )
            let configuration = Self.configuration(for: display.displayID)
            let image: CGImage
            if #available(macOS 14.0, *) {
                image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: configuration
                )
            } else {
                image = try await OneShotStreamCapture.capture(filter: filter, configuration: configuration)
            }

            let scale = CGFloat(image.width) / max(screen.frame.width, 1)
            let windows = detectedWindows.filter { $0.frame.intersects(screen.frame) }
            captures.append(CapturedDisplay(
                displayID: display.displayID,
                screenFrame: screen.frame,
                scale: scale,
                image: image,
                windows: windows
            ))
        }

        guard !captures.isEmpty else { throw ScreenCaptureError.noDisplays }
        return captures
    }

    static func configuration(for displayID: CGDirectDisplayID) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = max(Int(CGDisplayPixelsWide(displayID)), 1)
        configuration.height = max(Int(CGDisplayPixelsHigh(displayID)), 1)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = 1
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.colorSpaceName = CGColorSpace.sRGB
        return configuration
    }

    static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }
    }
}

private final class OneShotStreamCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let processingQueue = DispatchQueue(label: "com.cutscreen.single-frame", qos: .userInitiated)
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private var continuation: CheckedContinuation<CGImage, any Error>?
    private var stream: SCStream?
    private var finished = false

    static func capture(filter: SCContentFilter, configuration: SCStreamConfiguration) async throws -> CGImage {
        let capture = OneShotStreamCapture()
        return try await capture.start(filter: filter, configuration: configuration)
    }

    private func start(filter: SCContentFilter, configuration: SCStreamConfiguration) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            self.stream = stream
            do {
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: processingQueue)
            } catch {
                finish(.failure(error))
                return
            }
            Task {
                do {
                    try await stream.startCapture()
                } catch {
                    finish(.failure(error))
                }
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        finish(.failure(error))
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              sampleBuffer.isValid,
              let imageBuffer = sampleBuffer.imageBuffer else { return }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let statusValue = attachments.first?[.status] as? Int,
           SCFrameStatus(rawValue: statusValue) != .complete {
            return
        }

        let image = CIImage(cvPixelBuffer: imageBuffer)
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else {
            finish(.failure(ScreenCaptureError.invalidFrame))
            return
        }
        finish(.success(cgImage))
    }

    private func finish(_ result: Result<CGImage, any Error>) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        let stream = self.stream
        lock.unlock()

        continuation?.resume(with: result)
        if let stream {
            Task { try? await stream.stopCapture() }
        }
    }
}
