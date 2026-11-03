import AppKit
import XCTest
@testable import Ogle

/// The text editor's text, whether it has unsaved changes, and the file's contents.
struct EditorState: Equatable {
    var text: String
    var unsaved: Bool
    var file: String
}

@MainActor
final class TextEditorTests: XCTestCase {
    /// A text editor in a window of its own, showing a new file holding `text`.
    func makeEditor(_ text: String) throws -> (TextEditorViewController, URL) {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ogle-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "document.md")
        try text.write(to: url, atomically: true, encoding: .utf8)
        NSApplication.shared.setActivationPolicy(.accessory)
        let editor = TextEditorViewController()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = editor.view
        try editor.open(url, atLine: nil)
        addTeardownBlock { @MainActor in
            window.close()
            try FileManager.default.removeItem(at: directory)
        }
        return (editor, url)
    }

    func type(_ text: String, into editor: TextEditorViewController) {
        let textView = editor.focusView as! NSTextView
        textView.insertText(text, replacementRange: textView.selectedRange())
        // Ends the undo group, as the end of the event does.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    }

    func state(of editor: TextEditorViewController, _ url: URL) throws -> EditorState {
        EditorState(
            text: (editor.focusView as! NSTextView).string, unsaved: editor.hasUnsavedChanges,
            file: try String(contentsOf: url, encoding: .utf8))
    }

    func testSavingWritesTheText() throws {
        let (editor, url) = try makeEditor("text")
        type("new ", into: editor)
        editor.save()
        XCTAssertEqual(try state(of: editor, url), EditorState(text: "new text", unsaved: false, file: "new text"))
    }

    func testTypingMakesUnsavedChanges() throws {
        let (editor, url) = try makeEditor("text")
        type("new ", into: editor)
        XCTAssertEqual(try state(of: editor, url), EditorState(text: "new text", unsaved: true, file: "text"))
    }

    func testUndoingBackToTheSavedTextLeavesNoUnsavedChanges() throws {
        let (editor, url) = try makeEditor("text")
        type("new ", into: editor)
        editor.focusView.undoManager!.undo()
        XCTAssertEqual(try state(of: editor, url), EditorState(text: "text", unsaved: false, file: "text"))
    }

    func testUndoAfterSavingUndoesOnlyWhatWasTypedSince() throws {
        let (editor, url) = try makeEditor("text")
        type("a", into: editor)
        editor.save()
        type("b", into: editor)
        editor.focusView.undoManager!.undo()
        XCTAssertEqual(try state(of: editor, url), EditorState(text: "atext", unsaved: false, file: "atext"))
    }

    func testShowingAnotherFileKeepsUnsavedChanges() throws {
        let (editor, url) = try makeEditor("text")
        let other = url.deletingLastPathComponent().appending(path: "other.md")
        try "other".write(to: other, atomically: true, encoding: .utf8)
        type("new ", into: editor)
        try editor.open(other, atLine: nil)
        let whileAway = editor.hasUnsavedChanges
        try editor.open(url, atLine: nil)
        XCTAssertEqual(
            [whileAway ? "unsaved" : "saved", try state(of: editor, url).text],
            ["unsaved", "new text"])
    }

    func testReloadsWhenAnotherAppChangesTheFile() throws {
        let (editor, url) = try makeEditor("text")
        try "changed".write(to: url, atomically: true, encoding: .utf8)
        let textView = editor.focusView as! NSTextView
        let deadline = Date(timeIntervalSinceNow: 5)
        while textView.string != "changed" && Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        XCTAssertEqual(try state(of: editor, url), EditorState(text: "changed", unsaved: false, file: "changed"))
    }
}
