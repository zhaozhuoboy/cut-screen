import AppKit

protocol WindowDetecting {
    @MainActor func windows() -> [DetectedWindow]
}

struct SystemWindowDetector: WindowDetecting {
    @MainActor
    func windows() -> [DetectedWindow] {
        guard let rawWindows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]], let primaryScreen = NSScreen.screens.first else {
            return []
        }

        let primaryTop = primaryScreen.frame.maxY
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return rawWindows.compactMap { info in
            guard let number = info[kCGWindowNumber as String] as? NSNumber,
                  let ownerPID = info[kCGWindowOwnerPID as String] as? NSNumber,
                  ownerPID.int32Value != ownPID,
                  let layer = info[kCGWindowLayer as String] as? NSNumber,
                  layer.intValue == 0,
                  let boundsDictionary = info[kCGWindowBounds as String] as? [String: Any],
                  let quartzFrame = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
                  quartzFrame.width >= 40,
                  quartzFrame.height >= 30 else {
                return nil
            }

            let cocoaFrame = CGRect(
                x: quartzFrame.minX,
                y: primaryTop - quartzFrame.maxY,
                width: quartzFrame.width,
                height: quartzFrame.height
            )
            return DetectedWindow(
                windowID: CGWindowID(number.uint32Value),
                ownerName: info[kCGWindowOwnerName as String] as? String ?? "",
                frame: cocoaFrame,
                layer: layer.intValue
            )
        }
    }
}
