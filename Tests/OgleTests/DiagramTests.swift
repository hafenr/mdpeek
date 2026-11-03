import XCTest
@testable import Ogle

/// A diagram open on its own over the preview zooms and pans by itself, while the page behind
/// it and the editor stay where they are; the editor still scrolls, and while linked the page
/// behind follows it. For each editor, in the subclasses.
@MainActor
class DiagramTests: EditorTestCase {
    /// A window with the editor and the preview at line 120, linked, and the diagram open, with
    /// the diagram's view.
    func makeWindowWithDiagram() throws -> (TestWindow, [Double]) {
        let window = try makeWindow()
        window.scrollEditor(toLine: 120)
        _ = try window.tops(becoming: Tops(editor: 120, preview: 120))
        try window.openDiagram()
        return (window, try window.diagramView()!)
    }

    func testScrollingTheDiagramPansIt() throws {
        let (window, fit) = try makeWindowWithDiagram()
        window.scrollWheelOverPreview(lines: 5)
        XCTAssertEqual(try window.diagramChange(from: fit), ["down"])
    }

    func testScrollingTheDiagramLeavesThePageAndTheEditor() throws {
        let (window, _) = try makeWindowWithDiagram()
        window.scrollWheelOverPreview(lines: 5)
        XCTAssertEqual(try window.tops(after: 1), Tops(editor: 120, preview: 120))
    }

    func testCommandScrollingTheDiagramZoomsIt() throws {
        let (window, fit) = try makeWindowWithDiagram()
        window.scrollWheelOverPreview(lines: -5, command: true)
        XCTAssertEqual(try window.diagramChange(from: fit), ["in"])
    }

    func testCommandScrollingTheDiagramLeavesThePageAndTheEditor() throws {
        let (window, _) = try makeWindowWithDiagram()
        window.scrollWheelOverPreview(lines: -5, command: true)
        XCTAssertEqual(try window.tops(after: 1), Tops(editor: 120, preview: 120))
    }

    func testDraggingTheDiagramToTheRightShowsWhatIsLeftOfIt() throws {
        let (window, fit) = try makeWindowWithDiagram()
        window.dragOverPreview(by: CGSize(width: 100, height: 0))
        XCTAssertEqual(try window.diagramChange(from: fit), ["left"])
    }

    func testPinchingTheDiagramZoomsIt() throws {
        let (window, fit) = try makeWindowWithDiagram()
        try window.pinchDiagram(to: 2)
        XCTAssertEqual(Array(try window.diagramView()![2...]), [(fit[2] / 2).rounded(), (fit[3] / 2).rounded()])
    }

    func testZoomShortcutsZoomTheDiagramRatherThanThePageOrTheEditor() throws {
        let (window, fit) = try makeWindowWithDiagram()
        window.controller.zoomIn(nil)
        _ = try window.tops(after: 0.3)
        XCTAssertEqual(
            [try window.diagramView()![2], window.controller.preview.zoom, window.controller.editor.zoom],
            [(fit[2] / 1.25).rounded(), 1, 1])
    }

    func testActualSizeFitsTheDiagramAgain() throws {
        let (window, fit) = try makeWindowWithDiagram()
        window.controller.zoomIn(nil)
        window.scrollWheelOverPreview(lines: 5)
        window.controller.actualSize(nil)
        _ = try window.tops(after: 0.3)
        XCTAssertEqual(try window.diagramView(), fit)
    }

    func testThePageMagnifiesAgainOnceTheDiagramIsClosed() throws {
        let (window, _) = try makeWindowWithDiagram()
        let whileOpen = window.controller.preview.webView.allowsMagnification
        try window.closeDiagram()
        XCTAssertEqual([whileOpen, window.controller.preview.webView.allowsMagnification], [false, true])
    }

    func testClosingTheDiagramLeavesThePanesWhereTheyWere() throws {
        let (window, _) = try makeWindowWithDiagram()
        window.scrollWheelOverPreview(lines: 5)
        window.scrollWheelOverPreview(lines: -3, command: true)
        try window.closeDiagram()
        XCTAssertEqual(try window.tops(after: 1), Tops(editor: 120, preview: 120))
    }

    func testScrollingTheEditorUnlinkedLeavesThePage() throws {
        let (window, _) = try makeWindowWithDiagram()
        window.controller.toggleLinked(nil)
        window.scrollEditor(toLine: 60)
        XCTAssertEqual(try window.tops(after: 1), Tops(editor: 60, preview: 120))
    }

    func testScrollingTheEditorLinkedMovesThePageBehindTheDiagram() throws {
        let (window, _) = try makeWindowWithDiagram()
        let expected = Tops(editor: 60, preview: 60)
        window.scrollEditor(toLine: 60)
        XCTAssertEqual(try window.tops(becoming: expected), expected)
    }

    func testScrollingTheEditorLeavesTheDiagram() throws {
        let (window, fit) = try makeWindowWithDiagram()
        window.scrollEditor(toLine: 60)
        _ = try window.tops(after: 1)
        XCTAssertEqual(try window.diagramView(), fit)
    }
}

final class NeovimDiagramTests: DiagramTests {
    override class var kind: EditorViewController.Kind? { .neovim }
}

final class TextEditorDiagramTests: DiagramTests {
    override class var kind: EditorViewController.Kind? { .text }
}
