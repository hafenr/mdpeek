import XCTest
@testable import Ogle

/// How the editor and the preview scroll together while linked, and apart while not; for each
/// editor, in the subclasses. In the test document, line 123 is a heading, 127 a long
/// paragraph, and 120 and 60 list items.
@MainActor
class LinkTests: EditorTestCase {

    // MARK: Linked

    func testScrollingTheEditorMovesThePreview() throws {
        let window = try makeWindow()
        let expected = Tops(editor: 120, preview: 120)
        window.scrollEditor(toLine: 120)
        XCTAssertEqual(try window.tops(becoming: expected), expected)
    }

    func testScrollingTheEditorIntoAParagraphMovesThePreviewAsFar() throws {
        let window = try makeWindow()
        let expected = Tops(editor: shown(127.5), preview: shown(127.5))
        window.scrollEditor(toLine: 127.5)
        XCTAssertEqual(try window.tops(becoming: expected), expected)
    }

    func testScrollingThePreviewMovesTheEditor() throws {
        let window = try makeWindow()
        let expected = Tops(editor: 120, preview: 120)
        try window.scrollPreview(toLine: 120)
        XCTAssertEqual(try window.tops(becoming: expected), expected)
    }

    func testScrollingThePreviewIntoAParagraphMovesTheEditorAsFar() throws {
        let window = try makeWindow()
        let expected = Tops(editor: shown(127.5), preview: 127.5)
        try window.scrollPreview(toLine: 127, fraction: 0.5)
        XCTAssertEqual(try window.tops(becoming: expected), expected)
    }

    func testShowingTheEditorShowsWhereThePreviewIs() throws {
        let window = try makeWindow()
        let expected = Tops(editor: 120, preview: 120)
        window.controller.toggleEditor(nil)
        try window.waitForThePageToTakeItsWidth()
        try window.scrollPreview(toLine: 120)
        _ = try window.tops(after: 0.5)
        window.controller.toggleEditor(nil)
        XCTAssertEqual(try window.tops(becoming: expected), expected)
    }

    // MARK: Unlinked, then linked

    func testUnlinkedScrollingTheEditorLeavesThePreview() throws {
        let window = try makeWindow()
        let expected = Tops(editor: 120, preview: 1)
        window.controller.toggleLinked(nil)
        window.scrollEditor(toLine: 120)
        XCTAssertEqual(try window.tops(after: 1), expected)
    }

    func testUnlinkedScrollingThePreviewLeavesTheEditor() throws {
        let window = try makeWindow()
        let expected = Tops(editor: 1, preview: 120)
        window.controller.toggleLinked(nil)
        try window.scrollPreview(toLine: 120)
        XCTAssertEqual(try window.tops(after: 1), expected)
    }

    func testLinkingAfterScrollingTheEditorMovesThePreview() throws {
        let window = try makeWindow()
        let expected = Tops(editor: 120, preview: 120)
        window.controller.toggleLinked(nil)
        window.scrollEditor(toLine: 120)
        _ = try window.tops(becoming: Tops(editor: 120, preview: 1))
        window.controller.toggleLinked(nil)
        XCTAssertEqual(try window.tops(becoming: expected), expected)
    }

    func testLinkingAfterScrollingTheEditorIntoAParagraphLeavesTheEditorWhereItIs() throws {
        let window = try makeWindow()
        let expected = Tops(editor: shown(127.5), preview: shown(127.5))
        window.controller.toggleLinked(nil)
        window.scrollEditor(toLine: 127.5)
        _ = try window.tops(becoming: Tops(editor: shown(127.5), preview: 1))
        window.controller.toggleLinked(nil)
        XCTAssertEqual(try window.tops(becoming: expected), expected)
    }

    func testLinkingAfterScrollingThePreviewIntoAParagraphMovesTheEditorAsFar() throws {
        let window = try makeWindow()
        let expected = Tops(editor: shown(127.5), preview: 127.5)
        window.controller.toggleLinked(nil)
        try window.scrollPreview(toLine: 127, fraction: 0.5)
        _ = try window.tops(becoming: Tops(editor: 1, preview: 127.5))
        window.controller.toggleLinked(nil)
        XCTAssertEqual(try window.tops(becoming: expected), expected)
    }

    func testLinkingAfterScrollingThePreviewMovesTheEditor() throws {
        let window = try makeWindow()
        let expected = Tops(editor: 120, preview: 120)
        window.controller.toggleLinked(nil)
        try window.scrollPreview(toLine: 120)
        _ = try window.tops(becoming: Tops(editor: 1, preview: 120))
        window.controller.toggleLinked(nil)
        XCTAssertEqual(try window.tops(becoming: expected), expected)
    }

    func testLinkingFollowsThePreviewScrolledAfterTheEditor() throws {
        let window = try makeWindow()
        let expected = Tops(editor: 120, preview: 120)
        window.controller.toggleLinked(nil)
        window.scrollEditor(toLine: 60)
        _ = try window.tops(becoming: Tops(editor: 60, preview: 1))
        try window.scrollPreview(toLine: 120)
        _ = try window.tops(becoming: Tops(editor: 60, preview: 120))
        window.controller.toggleLinked(nil)
        XCTAssertEqual(try window.tops(becoming: expected), expected)
    }

    func testLinkingFollowsTheEditorScrolledAfterThePreview() throws {
        let window = try makeWindow()
        let expected = Tops(editor: 60, preview: 60)
        window.controller.toggleLinked(nil)
        try window.scrollPreview(toLine: 120)
        _ = try window.tops(becoming: Tops(editor: 1, preview: 120))
        window.scrollEditor(toLine: 60)
        _ = try window.tops(becoming: Tops(editor: 60, preview: 120))
        window.controller.toggleLinked(nil)
        XCTAssertEqual(try window.tops(becoming: expected), expected)
    }

    // MARK: Switching editors

    func testSwitchingEditorsLinkedAlignsBothOnTheLine() throws {
        let window = try makeWindow()
        let expected = Tops(editor: 127, preview: 127)
        try window.scrollPreview(toLine: 127, fraction: 0.5)
        _ = try window.tops(becoming: Tops(editor: shown(127.5), preview: 127.5))
        window.controller.switchEditor(to: Self.kind == .neovim ? .text : .neovim)
        XCTAssertEqual(try window.tops(becoming: expected), expected)
    }

    func testSwitchingEditorsUnlinkedKeepsBothWhereTheyAre() throws {
        let window = try makeWindow()
        let expected = Tops(editor: 60, preview: 120)
        window.controller.toggleLinked(nil)
        window.scrollEditor(toLine: 60)
        try window.scrollPreview(toLine: 120)
        _ = try window.tops(becoming: expected)
        window.controller.switchEditor(to: Self.kind == .neovim ? .text : .neovim)
        XCTAssertEqual(try window.tops(becoming: expected), expected)
    }

    // MARK: Resizing

    func testResizingKeepsTheLineTheEditorLedTo() throws {
        let window = try makeWindow()
        let expected = [Tops(editor: 127, preview: 127), Tops(editor: 127, preview: 127)]
        window.scrollEditor(toLine: 127)
        _ = try window.tops(becoming: expected[0])
        try window.resize(toWidth: 900)
        let narrower = try window.tops(after: 1)
        try window.resize(toWidth: 1500)
        XCTAssertEqual([narrower, try window.tops(after: 1)], expected)
    }

    func testResizingKeepsTheLineThePreviewLedTo() throws {
        let window = try makeWindow()
        let expected = [Tops(editor: 127, preview: 127), Tops(editor: 127, preview: 127)]
        try window.scrollPreview(toLine: 127)
        _ = try window.tops(becoming: expected[0])
        try window.resize(toWidth: 900)
        let narrower = try window.tops(after: 1)
        try window.resize(toWidth: 1500)
        XCTAssertEqual([narrower, try window.tops(after: 1)], expected)
    }

    func testResizingUnlinkedKeepsEachPaneWhereItIs() throws {
        let window = try makeWindow()
        let expected = [Tops(editor: 60, preview: 127), Tops(editor: 60, preview: 127)]
        window.controller.toggleLinked(nil)
        window.scrollEditor(toLine: 60)
        try window.scrollPreview(toLine: 127)
        _ = try window.tops(becoming: expected[0])
        try window.resize(toWidth: 900)
        let narrower = try window.tops(after: 1)
        try window.resize(toWidth: 1500)
        XCTAssertEqual([narrower, try window.tops(after: 1)], expected)
    }

    // MARK: The outline

    func testJumpingToAHeadingMovesTheEditorToIt() throws {
        let window = try makeWindow()
        let expected = Tops(editor: 123, preview: 123)
        window.jumpToHeading(atLine: 123)
        XCTAssertEqual(try window.tops(becoming: expected), expected)
    }

    func testJumpingToAHeadingUnlinkedLeavesTheEditorUntilLinked() throws {
        let window = try makeWindow()
        let expected = [Tops(editor: 1, preview: 123), Tops(editor: 123, preview: 123)]
        window.controller.toggleLinked(nil)
        window.jumpToHeading(atLine: 123)
        let unlinked = try window.tops(after: 1.5)
        window.controller.toggleLinked(nil)
        XCTAssertEqual([unlinked, try window.tops(becoming: expected[1])], expected)
    }
}

final class NeovimLinkTests: LinkTests {
    override class var kind: EditorViewController.Kind? { .neovim }
}

final class TextEditorLinkTests: LinkTests {
    override class var kind: EditorViewController.Kind? { .text }
}
