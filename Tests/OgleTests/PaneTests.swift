import AppKit
import SwiftTerm
import XCTest
@testable import Ogle

/// The editor pane: chosen in Settings, and with its text away from the pane's edges. For each
/// editor, in the subclasses.
@MainActor
class PaneTests: EditorTestCase {
    func testSettingsShowTheEditorAndSwitchToAnother() throws {
        let window = try makeWindow()
        let settings = SettingsWindowController(mainWindow: window.controller)
        let shown = settings.editorPopUp.titleOfSelectedItem
        settings.editorPopUp.selectItem(withTitle: otherKind.title)
        settings.editorPopUp.sendAction(settings.editorPopUp.action, to: settings.editorPopUp.target)
        XCTAssertEqual(
            [shown, window.controller.editor.kind.title, window.runningEditor?.title, settings.editorPopUp.titleOfSelectedItem],
            [Self.kind!.title, otherKind.title, otherKind.title, otherKind.title])
    }

    /// Without line numbers, as both editors start here.
    func testTheTextStartsAwayFromThePanesLeftEdge() throws {
        let window = try makeWindow()
        let pane = window.controller.editor.view
        let start: () -> CGFloat = {
            switch window.controller.editor.focusView {
            case let textView as NSTextView:
                textView.convert(
                    NSPoint(x: textView.textContainerOrigin.x + textView.textContainer!.lineFragmentPadding, y: 0), to: pane).x
            case let terminal as TerminalView:
                terminal.convert(NSPoint.zero, to: pane).x
            default:
                0
            }
        }
        _ = try? window.wait("the text to move from the edge", timeout: 3) { start() >= 8 }
        XCTAssertGreaterThanOrEqual(start(), 8)
    }
}

final class NeovimPaneTests: PaneTests {
    override class var kind: EditorViewController.Kind? { .neovim }

    func testNeovimFillsThePaneToItsOtherEdges() throws {
        let window = try makeWindow()
        let pane = window.controller.editor.view
        let frame = window.controller.editor.focusView!.frame
        XCTAssertEqual(
            [pane.safeAreaRect.maxY - frame.maxY, pane.bounds.maxX - frame.maxX, frame.minY - pane.bounds.minY],
            [0, 0, 0])
    }

    /// Line numbers and signs keep Neovim's text from the edge themselves.
    func testNeovimIsInsetOnlyWhileItsTextStartsAtTheLeftEdge() throws {
        let window = try makeWindow()
        let terminal = window.controller.editor.focusView as! TerminalView
        func inset(after command: String?, becoming expected: CGFloat) throws -> CGFloat {
            if let command { terminal.send(txt: "\u{1b}:\(command)\r") }
            _ = try? window.wait("the inset to become \(expected)", timeout: 3) { terminal.frame.minX == expected }
            return terminal.frame.minX
        }
        XCTAssertEqual(
            [
                try inset(after: nil, becoming: 12), try inset(after: "set number", becoming: 0),
                try inset(after: "set nonumber", becoming: 12), try inset(after: "set signcolumn=yes", becoming: 0),
                try inset(after: "set signcolumn=no relativenumber", becoming: 0),
            ],
            [12, 0, 12, 0, 0])
    }

    func testTheMarginAroundNeovimHasItsBackground() throws {
        let window = try makeWindow()
        let pane = window.controller.editor.view
        let terminal = window.controller.editor.focusView as! TerminalView
        let neovim = { pane.resolvedCGColor(terminal.nativeBackgroundColor) }
        _ = try? window.wait("the margin to take Neovim's background", timeout: 3) {
            pane.layer?.backgroundColor == neovim()
        }
        XCTAssertEqual(pane.layer?.backgroundColor, neovim())
    }
}

final class TextEditorPaneTests: PaneTests {
    override class var kind: EditorViewController.Kind? { .text }
}
