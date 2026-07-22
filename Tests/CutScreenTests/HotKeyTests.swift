import XCTest
@testable import CutScreen

final class HotKeyTests: XCTestCase {
    func testDefaultShortcut() {
        let shortcut = HotKey.default
        XCTAssertTrue(shortcut.isValid)
        XCTAssertEqual(shortcut.displayName, "⌃⌘A")
    }

    func testShortcutRequiresCommandControlOrOption() {
        let shortcut = HotKey(keyCode: 0, modifiers: [.shift])
        XCTAssertFalse(shortcut.isValid)
    }

    func testCodableRoundTrip() throws {
        let shortcut = HotKey.default
        let data = try JSONEncoder().encode(shortcut)
        XCTAssertEqual(try JSONDecoder().decode(HotKey.self, from: data), shortcut)
    }
}
