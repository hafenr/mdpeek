import AppKit
import SwiftTerm
import XCTest
@testable import Ogle

/// Where the tops of the editor and of the preview are, as source lines and how far through
/// them: 127.5 is halfway through the rows line 127 wraps to in the editor, and halfway
/// through its block in the preview, for a block that is that one line.
struct Tops: Equatable {
    var editor: Double?
    var preview: Double?
}

struct Timeout: Error, CustomStringConvertible {
    let description: String
}

/// Tests that run for each editor, in subclasses that set `kind`.
@MainActor
class EditorTestCase: XCTestCase {
    class var kind: EditorViewController.Kind? { nil }

    /// Where the editor's top goes when asked for `line`: Neovim shows whole lines only.
    func shown(_ line: Double) -> Double {
        Self.kind == .neovim ? line.rounded(.down) : line
    }

    var otherKind: EditorViewController.Kind { Self.kind == .neovim ? .text : .neovim }

    func makeWindow() throws -> TestWindow {
        guard let kind = Self.kind else { throw XCTSkip("Runs in the subclasses, for each editor") }
        let window = try TestWindow(kind: kind)
        addTeardownBlock { @MainActor in window.close() }
        return window
    }
}

/// Ogle's window on a generated document, with the editor shown, out of sight: transparent,
/// behind other windows and ignoring the mouse. Neovim runs with a HOME of its own, so without
/// the user's configuration. Needs the app built by build.sh, whose resources it uses.
@MainActor
final class TestWindow {
    /// Every line that is not blank holds "L" and its number, which tells which line the
    /// editor shows first.
    static let document: String = {
        let words = "lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor"
        var lines = ["# L1 Ogle test document", ""]
        for section in 0..<40 {
            let line = lines.count + 1
            lines += [
                "## L\(line) Section \(section)", "",
                "L\(line + 2) A short paragraph.", "",
                "L\(line + 4) A long paragraph: " + Array(repeating: words, count: 12).joined(separator: " "), "",
                "- L\(line + 6) An item", "- L\(line + 7) An item", "- L\(line + 8) An item", "",
            ]
        }
        lines += ["```mermaid", "flowchart LR", "  A[Start] --> B[Middle] --> C[End]", "```"]
        return lines.joined(separator: "\n")
    }()

    let controller: MainWindowController
    let url: URL
    private let directory: URL

    init(kind: EditorViewController.Kind) throws {
        let repository = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let resources = repository.appending(path: "build/Ogle.app/Contents/Resources")
        guard FileManager.default.fileExists(atPath: resources.appending(path: "web/index.html").path) else {
            throw Timeout(description: "No app at \(resources.path): run ./build.sh first")
        }
        directory = FileManager.default.temporaryDirectory.appending(path: "ogle-tests-\(UUID().uuidString)")
        let home = directory.appending(path: "home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        url = directory.appending(path: "document.md")
        try Self.document.write(to: url, atomically: true, encoding: .utf8)

        NSApplication.shared.setActivationPolicy(.accessory)
        controller = MainWindowController(resources: resources, editorEnvironment: ["HOME": home.path])
        controller.editor.kind = kind
        let window = controller.window!
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.setFrame(NSRect(x: 80, y: 80, width: 1200, height: 800), display: false)
        window.orderBack(nil)
        // Otherwise WebKit treats the page as hidden behind other windows, and pauses its
        // animation frames, which report the preview's scrolling.
        controller.preview.webView.perform(NSSelectorFromString("_setWindowOcclusionDetectionEnabled:"), with: nil)
        controller.open(url)
        try wait("the preview to show the document") {
            try self.script("return document.querySelectorAll('#content [data-sourcepos]').length") as? Int ?? 0 > 0
        }
        controller.toggleEditor(nil)
        try wait("the editor to show the document") { self.editorTop() == 1 }
        try waitForThePageToTakeItsWidth()
    }

    /// The page learns of a new width late: a scroll before then is undone, as its resize
    /// handler puts the line it follows back at the top.
    func waitForThePageToTakeItsWidth() throws {
        let webView = controller.preview.webView!
        try wait("the page to take the width of the preview") {
            try self.script("return innerWidth") as? Int == Int(webView.bounds.width)
        }
    }

    func close() {
        controller.editor.stop()
        controller.window?.close()
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: Acting as the user

    /// Scrolls the editor as the user would, so that `line` is at the top: partway through its
    /// rows in the text editor, while Neovim shows whole lines.
    func scrollEditor(toLine line: Double) {
        switch controller.editor.focusView {
        case let textView as NSTextView:
            // As the user scrolling there would.
            textView.layoutManager!.ensureLayout(for: textView.textContainer!)
            let rows = Self.rows(ofLine: Int(line), in: textView)
            let y = rows.lowerBound + (line - line.rounded(.down)) * (rows.upperBound - rows.lowerBound)
            textView.scroll(NSPoint(x: 0, y: y + textView.textContainerOrigin.y))
        case let terminal as TerminalView:
            terminal.send(txt: "\u{1b}:\(Int(line))\rzt")
        default:
            XCTFail("No editor")
        }
    }

    /// Scrolls the preview as the user would, so that its top is `fraction` of the way through
    /// the block of `line`.
    func scrollPreview(toLine line: Int, fraction: Double = 0) throws {
        try script("""
            const element = [...document.querySelectorAll("#content [data-sourcepos]")]
              .find((element) => element.dataset.sourcepos.startsWith(`${line}:`));
            const rect = element.getBoundingClientRect();
            window.scrollTo(0, rect.top + scrollY + fraction * rect.height);
            """, ["line": line, "fraction": fraction])
    }

    /// Jumps to the heading of `line` as the outline in the sidebar does.
    func jumpToHeading(atLine line: Int) {
        let heading = controller.preview.headings.first { $0.title.hasPrefix("L\(line) ") }!
        controller.preview.scrollToHeading(heading.id)
    }

    /// Opens the diagram at the end of the document on its own, as its "Open full window" button does.
    func openDiagram() throws {
        try wait("the diagram to render") {
            try self.script("return document.querySelector('.mermaid-figure .mermaid-diagram svg') !== null") as? Bool == true
        }
        try script("document.querySelector('.mermaid-figure [data-action=\"expand\"]').click()")
        try wait("the diagram to open") { self.controller.preview.showsLightbox }
    }

    func closeDiagram() throws {
        try script("document.querySelector('.lightbox [data-action=\"close\"]').click()")
        try wait("the diagram to close") { !self.controller.preview.showsLightbox }
    }

    /// The open diagram's viewBox: x, y, width and height, rounded.
    func diagramView() throws -> [Double]? {
        try script("""
            const svg = document.querySelector(".lightbox svg");
            return svg && svg.getAttribute("viewBox").split(" ").map((value) => Math.round(Number(value)));
            """) as? [Double]
    }

    /// Which way the open diagram's view moved since it was `before`, as a scroll moves it:
    /// "down" shows what is below. A change of size is "in" or "out", for zooming.
    func diagramChange(from before: [Double]) throws -> [String] {
        let after = try diagramView()!
        guard after[2] == before[2] else { return [after[2] < before[2] ? "in" : "out"] }
        return [
            after[0] < before[0] ? "left" : after[0] > before[0] ? "right" : nil,
            after[1] < before[1] ? "up" : after[1] > before[1] ? "down" : nil,
        ].compactMap { $0 }
    }

    /// Turns the mouse's scroll wheel over the middle of the preview, down for positive lines,
    /// with Command held if asked.
    func scrollWheelOverPreview(lines: Int32, command: Bool = false) {
        let webView = controller.preview.webView!
        let center = webView.convert(NSPoint(x: webView.bounds.midX, y: webView.bounds.midY), to: nil)
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: -lines, wheel2: 0, wheel3: 0)!
        // An event without a window gives its location on the screen as its location in the
        // window, which the web view reads: the screen point that is the window's.
        event.location = CGPoint(x: center.x, y: NSScreen.screens[0].frame.height - center.y)
        // Otherwise the keys held on the keyboard at the time.
        event.flags = command ? .maskCommand : []
        webView.scrollWheel(with: NSEvent(cgEvent: event)!)
        // The page gets it later than scripts run after it.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
    }

    /// Drags the mouse across the middle of the preview by `distance`, in the window's coordinates.
    func dragOverPreview(by distance: CGSize) {
        let webView = controller.preview.webView!
        let start = webView.convert(NSPoint(x: webView.bounds.midX, y: webView.bounds.midY), to: nil)
        let number = controller.window!.windowNumber
        func event(_ type: NSEvent.EventType, _ fraction: CGFloat) -> NSEvent {
            NSEvent.mouseEvent(
                with: type, location: NSPoint(x: start.x + distance.width * fraction, y: start.y + distance.height * fraction),
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: number, context: nil,
                eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
        }
        webView.mouseDown(with: event(.leftMouseDown, 0))
        for step in 1...10 {
            webView.mouseDragged(with: event(.leftMouseDragged, CGFloat(step) / 10))
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        webView.mouseUp(with: event(.leftMouseUp, 1))
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
    }

    /// Pinches the open diagram to `scale`, as WebKit reports a trackpad's pinch to the page.
    func pinchDiagram(to scale: Double) throws {
        try script("""
            const overlay = document.querySelector(".lightbox");
            const gesture = (type, scale) => {
              const event = new Event(type, { bubbles: true, cancelable: true });
              Object.assign(event, { scale, clientX: innerWidth / 2, clientY: innerHeight / 2 });
              overlay.dispatchEvent(event);
            };
            gesture("gesturestart", 1);
            gesture("gesturechange", (1 + scale) / 2);
            gesture("gesturechange", scale);
            gesture("gestureend", scale);
            """, ["scale": scale])
    }

    func resize(toWidth width: CGFloat) throws {
        let window = controller.window!
        window.setFrame(NSRect(origin: window.frame.origin, size: NSSize(width: width, height: window.frame.height)), display: true)
        try waitForThePageToTakeItsWidth()
    }

    // MARK: Observing

    /// The editor running in the pane, as its view tells.
    var runningEditor: EditorViewController.Kind? {
        switch controller.editor.focusView {
        case is NSTextView: .text
        case is TerminalView: .neovim
        default: nil
        }
    }

    /// The tops once they are `expected`, or as they are when that does not happen in time.
    func tops(becoming expected: Tops) throws -> Tops {
        do {
            try wait("the tops to become \(expected)", timeout: 5) { try self.tops() == expected }
        } catch is Timeout {}
        return try tops()
    }

    /// The tops after waiting long enough for either pane to follow the other.
    func tops(after seconds: TimeInterval) throws -> Tops {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds))
        return try tops()
    }

    func tops() throws -> Tops {
        Tops(editor: editorTop(), preview: try previewTop())
    }

    /// Where the editor's top is: in the text editor, the line of its first row and how far
    /// through the line's rows; in Neovim, the number on the first row of its screen, which only
    /// ever starts with a line.
    func editorTop() -> Double? {
        switch controller.editor.focusView {
        case let textView as NSTextView:
            let layoutManager = textView.layoutManager!
            guard layoutManager.numberOfGlyphs > 0 else { return nil }
            let y = max(textView.visibleRect.minY - textView.textContainerOrigin.y, 0)
            let glyph = layoutManager.glyphIndex(for: NSPoint(x: 0, y: y), in: textView.textContainer!)
            let index = layoutManager.characterIndexForGlyph(at: glyph)
            let line = textView.string.utf16.prefix(index).count { $0 == 0x0A } + 1
            let rows = Self.rows(ofLine: line, in: textView)
            return ((Double(line) + (y - rows.lowerBound) / (rows.upperBound - rows.lowerBound)) * 10).rounded() / 10
        case let terminal as TerminalView:
            // Neovim's screen, without scrollback.
            terminal.selectAll()
            let screen = terminal.getSelection() ?? ""
            terminal.selectNone()
            let row = screen.split(separator: "\n", omittingEmptySubsequences: false).first ?? ""
            return row.firstMatch(of: /L(\d+)/).flatMap { Double($0.1) }
        default:
            return nil
        }
    }

    /// Where the top of the preview is: in the innermost block it crosses, the block's first line
    /// plus how far through the block it is, in lines; between blocks, the next block's first line.
    func previewTop() throws -> Double? {
        try script("""
            let top = null;
            for (const element of document.querySelectorAll("#content [data-sourcepos]")) {
              const rect = element.getBoundingClientRect();
              if (!rect.height) continue;
              const [start, end] = element.dataset.sourcepos.match(/^(\\d+):\\d+-(\\d+)/).slice(1).map(Number);
              if (rect.top > 0.5) {
                top ??= start;
                break;
              }
              if (rect.bottom > 0.5) top = start + (-rect.top / rect.height) * (end - start + 1);
              else top = null;
            }
            return top === null ? null : Math.round(top * 10) / 10;
            """) as? Double
    }

    // MARK: Helpers

    @discardableResult
    func script(_ body: String, _ arguments: [String: Any] = [:]) throws -> Any? {
        var result: Result<Any, Error>?
        controller.preview.webView.callAsyncJavaScript(body, arguments: arguments, in: nil, in: .page) { result = $0 }
        try wait("the page to run a script") { result != nil }
        return try result!.get()
    }

    /// Runs the main run loop until `condition` holds.
    func wait(_ what: String, timeout: TimeInterval = 10, until condition: () throws -> Bool) throws {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while try !condition() {
            guard Date() < deadline else { throw Timeout(description: "Timed out waiting for \(what)") }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        }
    }

    /// The top and bottom of the rows `line` wraps to in the text view's container.
    static func rows(ofLine line: Int, in textView: NSTextView) -> Range<CGFloat> {
        let layoutManager = textView.layoutManager!
        let start = offset(ofLine: line, in: textView.string)
        let end = offset(ofLine: line + 1, in: textView.string) - 1
        let first = layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: start), effectiveRange: nil)
        let last = layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: end), effectiveRange: nil)
        return first.minY..<last.maxY
    }

    static func offset(ofLine line: Int, in text: String) -> Int {
        var remaining = line - 1
        for (offset, unit) in text.utf16.enumerated() where remaining > 0 && unit == 0x0A {
            remaining -= 1
            if remaining == 0 { return offset + 1 }
        }
        return 0
    }
}
