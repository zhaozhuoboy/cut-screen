import AppKit
import UniformTypeIdentifiers

@MainActor
final class CaptureCoordinator {
    enum State: Equatable {
        case idle
        case permission
        case selecting
        case editing
        case scrolling
        case exporting
    }

    private(set) var state: State = .idle

    private let captureService: any ScreenCaptureProviding
    private let exporter: any ScreenshotExporting
    private let pasteboard: any PasteboardWriting
    private let pinManager = PinManager()

    private var overlayControllers: [CaptureOverlayController] = []
    private var activeOverlay: CaptureOverlayController?
    private var activeDisplay: CapturedDisplay?
    private var selection: Selection?
    private var document: CaptureDocument?
    private var toolbarController: CaptureToolbarController?
    private var appearanceToolbarController: CaptureAppearanceToolbarController?
    private var scrollSession: ScrollCaptureSession?
    private var scrollHUD: ScrollCaptureHUDController?
    private var sourceApplication: NSRunningApplication?

    init() {
        let detector = SystemWindowDetector()
        captureService = SystemScreenCaptureService(windowDetector: detector)
        exporter = ImageExporter()
        pasteboard = PasteboardService()
    }

    func begin() {
        guard state == .idle else { return }
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            sourceApplication = frontmost
        }
        state = .permission

        guard captureService.hasPermission() else {
            let granted = captureService.requestPermission()
            if !granted {
                presentPermissionHelp()
                state = .idle
                return
            }
            presentRestartNotice()
            state = .idle
            return
        }

        Task { await captureAndPresent() }
    }

    func cancel() {
        if state == .scrolling {
            let session = scrollSession
            scrollHUD?.close()
            Task { _ = try? await session?.stop() }
        }
        finishSession()
    }

    func finishScrolling() async {
        await completeScrolling(saveToFile: false)
    }

    private func saveScrolling() async {
        await completeScrolling(saveToFile: true)
    }

    private func completeScrolling(saveToFile: Bool) async {
        guard state == .scrolling, let session = scrollSession,
              let selection, let activeDisplay, let document else { return }
        state = .exporting
        scrollHUD?.close()
        scrollHUD = nil
        scrollSession = nil

        do {
            let image = try await session.stop()
            let frame = CapturedFrame(
                image: image,
                pointSize: CGSize(width: selection.localRect.width, height: CGFloat(image.height) / activeDisplay.scale),
                scale: activeDisplay.scale
            )
            document.replaceBase(with: frame)
            if saveToFile {
                activeOverlay?.window?.orderOut(nil)
                NSApplication.shared.activate(ignoringOtherApps: true)
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.png, .jpeg]
                panel.canCreateDirectories = true
                panel.nameFieldStringValue = ScreenshotFileName.make(extension: "png")
                guard panel.runModal() == .OK, let url = panel.url else {
                    restoreEditingAfterScroll()
                    return
                }
                let format: ExportFormat = ["jpg", "jpeg"].contains(url.pathExtension.lowercased()) ? .jpeg : .png
                try exporter.data(for: document, format: format).write(to: url, options: .atomic)
            } else {
                let data = try exporter.data(for: document, format: .png)
                guard pasteboard.writePNG(data) else { throw ImageExportError.encoding }
            }
            finishSession()
        } catch {
            restoreEditorAfterScrollFailure(
                error,
                title: document.pointSize.height > selection.localRect.height + 1
                    ? (saveToFile ? "保存长截图失败" : "复制长截图失败")
                    : "滚动长截图失败"
            )
        }
    }

    private func captureAndPresent() async {
        do {
            let displays = try await captureService.captureDisplays()
            guard state == .permission else { return }
            state = .selecting
            overlayControllers = displays.map { display in
                CaptureOverlayController(
                    display: display,
                    onSelection: { [weak self] display, rect in self?.commitSelection(display: display, localRect: rect) },
                    onSelectionAdjusted: { [weak self] rect in self?.adjustSelection(to: rect) },
                    onSelectionAdjustmentStateChanged: { [weak self] active in
                        self?.selectionAdjustmentStateChanged(isActive: active)
                    },
                    onDocumentChanged: { [weak self] in self?.documentChanged() },
                    onConfirm: { [weak self] in self?.copyAndFinish() },
                    onCancel: { [weak self] in self?.cancel() }
                )
            }
            for controller in overlayControllers { controller.window?.orderFrontRegardless() }
            overlayControllers.first?.window?.makeKey()
            NSApplication.shared.activate(ignoringOtherApps: true)
        } catch {
            state = .idle
            ErrorPresenter.show(title: "无法开始截图", error: error)
        }
    }

    private func commitSelection(display: CapturedDisplay, localRect: CGRect) {
        guard state == .selecting, let image = display.crop(localRect: localRect) else { return }
        let selection = Selection(displayID: display.displayID, screenFrame: display.screenFrame, localRect: localRect)
        let frame = CapturedFrame(image: image, pointSize: localRect.size, scale: display.scale)
        let document = CaptureDocument(frame: frame)

        activeDisplay = display
        self.selection = selection
        self.document = document
        activeOverlay = overlayControllers.first(where: { $0.display.displayID == display.displayID })
        for controller in overlayControllers where controller !== activeOverlay {
            controller.window?.orderOut(nil)
        }
        overlayControllers = [activeOverlay].compactMap { $0 }
        activeOverlay?.beginEditing(document: document, selectionRect: localRect)
        installToolbar()
        installAppearanceToolbar()
        toolbarController?.position(relativeTo: selection.globalRect, in: selection.screenFrame)
        toolbarController?.showWindow(nil)
        toolbarController?.window?.orderFrontRegardless()
        appearanceToolbarController?.position(relativeTo: selection.globalRect, in: selection.screenFrame)
        appearanceToolbarController?.showWindow(nil)
        appearanceToolbarController?.window?.orderFrontRegardless()
        state = .editing
    }

    private func adjustSelection(to localRect: CGRect) {
        guard state == .editing, let activeDisplay, let image = activeDisplay.crop(localRect: localRect),
              document?.hasAnnotations == false else { return }
        selection?.localRect = localRect
        let frame = CapturedFrame(image: image, pointSize: localRect.size, scale: activeDisplay.scale)
        document?.replaceBase(with: frame)
        if let document { activeOverlay?.beginEditing(document: document, selectionRect: localRect) }
        if let selection {
            toolbarController?.position(relativeTo: selection.globalRect, in: selection.screenFrame)
            appearanceToolbarController?.position(relativeTo: selection.globalRect, in: selection.screenFrame)
        }
        documentChanged()
    }

    private func selectionAdjustmentStateChanged(isActive: Bool) {
        guard state == .editing else { return }
        if isActive {
            toolbarController?.hideStylePanel()
            toolbarController?.window?.orderOut(nil)
            appearanceToolbarController?.window?.orderOut(nil)
            return
        }

        guard let selection else { return }
        toolbarController?.position(relativeTo: selection.globalRect, in: selection.screenFrame)
        appearanceToolbarController?.position(relativeTo: selection.globalRect, in: selection.screenFrame)
        toolbarController?.window?.orderFrontRegardless()
        appearanceToolbarController?.window?.orderFrontRegardless()
    }

    private func installToolbar() {
        guard toolbarController == nil else { return }
        toolbarController = CaptureToolbarController(actions: .init(
            toolChanged: { [weak self] tool in self?.activeOverlay?.overlayView.setTool(tool) },
            styleChanged: { [weak self] style in self?.activeOverlay?.overlayView.setStyle(style) },
            mosaicConfigurationChanged: { [weak self] configuration in
                self?.activeOverlay?.overlayView.setMosaicConfiguration(configuration)
            },
            undo: { [weak self] in self?.activeOverlay?.overlayView.undo() },
            redo: { [weak self] in self?.activeOverlay?.overlayView.redo() },
            scroll: { [weak self] in self?.startScrolling() },
            pin: { [weak self] in self?.pinCurrentImage() },
            save: { [weak self] in self?.saveCurrentImage() },
            cancel: { [weak self] in self?.cancel() },
            confirm: { [weak self] in self?.copyAndFinish() }
        ))
        documentChanged()
    }

    private func installAppearanceToolbar() {
        guard appearanceToolbarController == nil else { return }
        appearanceToolbarController = CaptureAppearanceToolbarController { [weak self] appearance in
            self?.document?.setAppearance(appearance)
            self?.activeOverlay?.overlayView.refreshAppearance()
        }
    }

    private func documentChanged() {
        guard let document else { return }
        toolbarController?.setHistory(canUndo: document.canUndo, canRedo: document.canRedo)
        toolbarController?.setScrollEnabled(!document.hasAnnotations && document.pointSize.height <= (selection?.localRect.height ?? 0) + 1)
    }

    private func startScrolling() {
        guard state == .editing, let document, !document.hasAnnotations,
              let selection, let activeDisplay else { return }
        state = .scrolling
        toolbarController?.hideStylePanel()
        activeOverlay?.beginScrollingMask(selectionRect: selection.localRect)
        toolbarController?.window?.orderOut(nil)
        appearanceToolbarController?.window?.orderOut(nil)

        let session = ScrollCaptureSession(selection: selection, scale: activeDisplay.scale)
        let hud = ScrollCaptureHUDController(
            selection: selection,
            onSave: { [weak self] in Task { await self?.saveScrolling() } },
            onCancel: { [weak self] in self?.cancel() },
            onFinish: { [weak self] in Task { await self?.finishScrolling() } }
        )
        session.onProgress = { [weak hud] result, totalHeight, preview in
            hud?.update(result: result, totalHeight: totalHeight, preview: preview)
        }
        session.onFailure = { [weak self] error in
            self?.restoreEditorAfterScrollFailure(error)
        }
        scrollSession = session
        scrollHUD = hud
        hud.show()

        Task {
            do {
                try await session.start()
                sourceApplication?.activate(options: [.activateIgnoringOtherApps])
            } catch {
                restoreEditorAfterScrollFailure(error)
            }
        }
    }

    private func restoreEditorAfterScrollFailure(
        _ error: any Error,
        title: String = "滚动长截图失败"
    ) {
        restoreEditingAfterScroll()
        ErrorPresenter.show(title: title, error: error)
    }

    private func restoreEditingAfterScroll() {
        scrollHUD?.close()
        scrollHUD = nil
        scrollSession = nil
        if let document, let selection {
            activeOverlay?.beginEditing(document: document, selectionRect: selection.localRect)
            toolbarController?.position(relativeTo: selection.globalRect, in: selection.screenFrame)
            appearanceToolbarController?.position(relativeTo: selection.globalRect, in: selection.screenFrame)
        }
        activeOverlay?.window?.orderFrontRegardless()
        toolbarController?.window?.orderFrontRegardless()
        appearanceToolbarController?.window?.orderFrontRegardless()
        state = .editing
        documentChanged()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func copyAndFinish() {
        guard state == .editing, let document else { return }
        state = .exporting
        do {
            let data = try exporter.data(for: document, format: .png)
            guard pasteboard.writePNG(data) else { throw ImageExportError.encoding }
            finishSession()
        } catch {
            state = .editing
            ErrorPresenter.show(title: "复制失败", error: error)
        }
    }

    private func saveCurrentImage() {
        guard state == .editing, let document else { return }
        activeOverlay?.window?.orderOut(nil)
        toolbarController?.window?.orderOut(nil)
        appearanceToolbarController?.window?.orderOut(nil)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = ScreenshotFileName.make(extension: "png")
        guard panel.runModal() == .OK, let url = panel.url else {
            restoreEditingWindows()
            return
        }
        let format: ExportFormat = ["jpg", "jpeg"].contains(url.pathExtension.lowercased()) ? .jpeg : .png

        state = .exporting
        do {
            try exporter.data(for: document, format: format).write(to: url, options: .atomic)
            finishSession()
        } catch {
            state = .editing
            restoreEditingWindows()
            ErrorPresenter.show(title: "保存失败", error: error)
        }
    }

    private func pinCurrentImage() {
        guard state == .editing, let document else { return }
        state = .exporting
        do {
            let image = try exporter.render(document)
            let pointSize = CGSize(
                width: CGFloat(image.width) / document.scale,
                height: CGFloat(image.height) / document.scale
            )
            finishSession()
            pinManager.pin(image, pointSize: pointSize)
        } catch {
            state = .editing
            ErrorPresenter.show(title: "贴图失败", error: error)
        }
    }

    private func finishSession() {
        scrollHUD?.close()
        toolbarController?.close()
        appearanceToolbarController?.close()
        for controller in overlayControllers { controller.close() }
        overlayControllers.removeAll()
        activeOverlay = nil
        activeDisplay = nil
        selection = nil
        document = nil
        toolbarController = nil
        appearanceToolbarController = nil
        scrollSession = nil
        scrollHUD = nil
        sourceApplication = nil
        state = .idle
    }

    private func restoreEditingWindows() {
        activeOverlay?.window?.orderFrontRegardless()
        toolbarController?.window?.orderFrontRegardless()
        appearanceToolbarController?.window?.orderFrontRegardless()
        activeOverlay?.window?.makeKey()
    }

    private func presentPermissionHelp() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "需要屏幕录制权限"
        alert.informativeText = "请在“系统设置 → 隐私与安全性 → 屏幕与系统音频录制”中允许轻截，然后重新启动应用。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func presentRestartNotice() {
        let alert = NSAlert()
        alert.messageText = "屏幕录制权限已申请"
        alert.informativeText = "macOS 通常需要重新启动应用后才能开始截图。请退出并重新打开轻截。"
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }
}
