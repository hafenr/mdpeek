import XCTest
@testable import Ogle

@MainActor
final class PreviewTests: XCTestCase {
    func testHeadingsOverSeveralLinesShowOnOneInTheOutlineAndTheStatusBar() throws {
        let window = try TestWindow(kind: .text)
        addTeardownBlock { @MainActor in window.close() }
        let url = window.url.deletingLastPathComponent().appending(path: "headings.md")
        try "---\ntitle: Front matter\n---\n\nA heading\nover two lines\n==============\n\n## Second\n"
            .write(to: url, atomically: true, encoding: .utf8)
        window.controller.open(url)
        _ = try? window.wait("the outline and the status bar", timeout: 5) {
            window.controller.preview.headings.count == 2 && window.statusBarSection()?.hasSuffix("of 2") == true
        }
        XCTAssertEqual(
            window.controller.preview.headings.map(\.title) + [window.statusBarSection()],
            ["A heading over two lines", "Second", "A heading over two lines · 1 of 2"])
    }
}
