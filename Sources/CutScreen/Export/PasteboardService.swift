import AppKit

protocol PasteboardWriting {
    func writePNG(_ data: Data) -> Bool
    func writeString(_ string: String) -> Bool
}

struct PasteboardService: PasteboardWriting {
    func writePNG(_ data: Data) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setData(data, forType: .png)
    }

    func writeString(_ string: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(string, forType: .string)
    }
}
