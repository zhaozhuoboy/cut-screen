import AppKit

protocol PasteboardWriting {
    func writePNG(_ data: Data) -> Bool
}

struct PasteboardService: PasteboardWriting {
    func writePNG(_ data: Data) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setData(data, forType: .png)
    }
}
