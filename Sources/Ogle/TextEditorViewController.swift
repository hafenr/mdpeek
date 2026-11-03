import AppKit

/// The editor pane's alternative to Neovim: a plain text view that edits as Mac apps do. Like
/// Neovim, it saves only when asked (⌘S), and keeps the files with unsaved changes it showed
/// before another one until they are saved or discarded.
@MainActor
final class TextEditorViewController: NSViewController, NSTextViewDelegate, NSTextStorageDelegate {
    /// A file in the editor, with its own text and undo history.
    @MainActor
    private final class Buffer {
        let url: URL
        let storage: NSTextStorage
        let undoManager = UndoManager()
        /// The text as last read or written.
        var savedText: String
        /// The file's modification date when last read or written, which tells whether another
        /// app changed it since.
        var modificationDate: Date?
        var selection = NSRange()
        var topLine: Double = 1

        init(url: URL) throws {
            self.url = url
            modificationDate = Self.modificationDate(of: url)
            savedText = try String(contentsOf: url, encoding: .utf8)
            storage = NSTextStorage(string: savedText)
        }

        var isModified: Bool { storage.string != savedText }

        /// Nil if the file is gone, which counts as a change too.
        static func modificationDate(of url: URL) -> Date? {
            try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        }
    }

    /// Called with the first line shown of a file, and how far through it the top is, whenever
    /// that changes, and when Ogle asks for it; the flag tells which.
    var onScroll: ((URL, Double, _ requested: Bool) -> Void)?
    var onCursorMove: ((URL, Int) -> Void)?
    var onUnsavedChangesChange: ((Bool) -> Void)?
    private(set) var hasUnsavedChanges = false {
        didSet {
            if hasUnsavedChanges != oldValue { onUnsavedChangesChange?(hasUnsavedChanges) }
        }
    }
    /// Keeps the line at the top in place as the text reflows.
    var font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular) {
        didSet {
            guard font != oldValue else { return }
            let line = topLine
            textView.font = font
            scroll(toLine: line)
        }
    }
    var focusView: NSView { textView }
    /// Asks whether to save over the file at the URL, which another app changed since it was read;
    /// tests answer for the user.
    var confirmOverwriting: (URL) -> Bool = { url in
        let alert = NSAlert()
        alert.messageText = "“\(url.lastPathComponent)” was changed by another app since you opened it."
        alert.informativeText = "Saving replaces those changes with the text in the editor."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Save Anyway")
        return alert.runModal() == .alertSecondButtonReturn
    }

    private let scrollView = ScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
    private let textView = NSTextView(usingTextLayoutManager: false)
    private var current: Buffer?
    /// The files with unsaved changes that another file replaced in the view.
    private var hidden: [URL: Buffer] = [:]
    private var watcher: FileWatcher?
    private var cachedLineStarts: [Int]?
    private var reportsScrolling = true
    private var reportedTopLine: Double?
    private var reportedCursorLine: Int?

    override func loadView() {
        scrollView.hasVerticalScroller = true
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.onScroll = { [weak self] in self?.scrolled() }
        // Keeps the line at the top in place as the text reflows.
        scrollView.aroundResize = { [weak self] resize in
            guard let self else { return resize() }
            let line = topLine
            reportsScrolling = false
            resize()
            scroll(toLine: line)
        }
        textView.frame = NSRect(origin: .zero, size: scrollView.contentSize)
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = .width
        textView.textContainer!.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.isRichText = false
        textView.allowsUndo = true
        // Until a file is open.
        textView.isEditable = false
        // Markdown is code as much as prose: no curly quotes, en dashes or corrections.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = font
        textView.delegate = self
        scrollView.documentView = textView
        view = scrollView
    }

    /// Shows the file at `url`, with `line` at the top if given. Without a line, reports where
    /// it shows the file.
    func open(_ url: URL, atLine line: Double?) throws {
        if url != current?.url {
            show(try hidden.removeValue(forKey: url) ?? Buffer(url: url))
        }
        if let line {
            scroll(toLine: line)
        } else if let current {
            let line = topLine
            reportedTopLine = line
            onScroll?(current.url, line, true)
        }
    }

    /// Scrolls so that `line` is at the top, if showing the file at `url`.
    func scroll(_ url: URL, toLine line: Double) {
        guard url == current?.url else { return }
        scroll(toLine: line)
    }

    /// Writes the file shown, after asking if another app changed it since it was read.
    func save() {
        guard let current else { return }
        if Buffer.modificationDate(of: current.url) != current.modificationDate {
            guard confirmOverwriting(current.url) else { return }
        }
        let text = current.storage.string
        do {
            // In place, as Neovim and most editors do, which keeps the file's permissions and
            // any links to it.
            try Data(text.utf8).write(to: current.url)
        } catch {
            presentError(error)
            return
        }
        current.savedText = text
        current.modificationDate = Buffer.modificationDate(of: current.url)
        // Undo then starts with what was typed after saving.
        textView.breakUndoCoalescing()
        updateUnsavedChanges()
    }

    private func show(_ buffer: Buffer) {
        if let current {
            textView.breakUndoCoalescing()
            current.selection = textView.selectedRange()
            current.topLine = topLine
            if current.isModified { hidden[current.url] = current }
        }
        current = buffer
        cachedLineStarts = nil
        buffer.storage.delegate = self
        reportsScrolling = false
        textView.layoutManager!.replaceTextStorage(buffer.storage)
        textView.font = font
        textView.textColor = .textColor
        textView.isEditable = true
        textView.setSelectedRange(buffer.selection)
        reportsScrolling = true
        scroll(toLine: buffer.topLine)
        watcher = FileWatcher(url: buffer.url) { [weak self] in self?.fileChanged() }
        reportedCursorLine = nil
        reportCursor()
        updateUnsavedChanges()
    }

    /// Reloads the file shown when another app changes it, unless it has unsaved changes, which
    /// saving then asks about.
    private func fileChanged() {
        // Atomic saves briefly remove the file; the event for the replacement follows.
        guard let current, !current.isModified, FileManager.default.fileExists(atPath: current.url.path) else { return }
        let modificationDate = Buffer.modificationDate(of: current.url)
        let text: String
        do {
            text = try String(contentsOf: current.url, encoding: .utf8)
        } catch {
            presentError(error)
            return
        }
        current.modificationDate = modificationDate
        guard text != current.savedText else { return }
        let line = topLine
        let selection = textView.selectedRange()
        reportsScrolling = false
        current.storage.replaceCharacters(in: NSRange(location: 0, length: current.storage.length), with: text)
        current.savedText = text
        current.undoManager.removeAllActions()
        textView.font = font
        textView.textColor = .textColor
        textView.setSelectedRange(NSRange(location: min(selection.location, current.storage.length), length: 0))
        scroll(toLine: line)
    }

    private func updateUnsavedChanges() {
        hasUnsavedChanges = !hidden.isEmpty || current?.isModified == true
    }

    // MARK: Lines

    /// The line at the top of the view, counting from 1, and how far through its wrapped rows the
    /// top is: 127.5 halfway through line 127.
    private var topLine: Double {
        let layoutManager = textView.layoutManager!
        guard layoutManager.numberOfGlyphs > 0 else { return 1 }
        let y = max(scrollView.contentView.bounds.minY - textView.textContainerOrigin.y, 0)
        let glyph = layoutManager.glyphIndex(for: NSPoint(x: 0, y: y), in: textView.textContainer!)
        let line = line(at: layoutManager.characterIndexForGlyph(at: glyph))
        guard let span = span(ofLine: line), !span.isEmpty else { return Double(line) }
        let through = min(max((y - span.lowerBound) / (span.upperBound - span.lowerBound), 0), 0.999)
        return Double(line) + (through * 1000).rounded(.down) / 1000
    }

    /// Scrolls so that `line` is at the top, without reporting it.
    private func scroll(toLine line: Double) {
        reportsScrolling = false
        defer {
            reportsScrolling = true
            reportedTopLine = topLine
        }
        let whole = Int(line)
        // The text view grows as the text is laid out, in the background otherwise, and until
        // then is too short to scroll that far.
        textView.layoutManager!.ensureLayout(for: textView.textContainer!)
        guard line > 1, whole <= lineStarts().count, let span = span(ofLine: whole) else {
            textView.scroll(NSPoint(x: 0, y: line > 1 ? textView.bounds.maxY : 0))
            return
        }
        let y = span.lowerBound + (line - Double(whole)) * (span.upperBound - span.lowerBound)
        textView.scroll(NSPoint(x: 0, y: y + textView.textContainerOrigin.y))
    }

    /// The top and bottom of the rows that `line` wraps to, in the text container; nil for the
    /// empty line after a final newline.
    private func span(ofLine line: Int) -> Range<CGFloat>? {
        let starts = lineStarts()
        let length = textView.textStorage!.length
        let start = starts[line - 1]
        guard start < length else { return nil }
        let end = line < starts.count ? starts[line] : length
        let layoutManager = textView.layoutManager!
        let first = layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: start), effectiveRange: nil)
        let last = layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: end - 1), effectiveRange: nil)
        return first.minY..<last.maxY
    }

    private func scrolled() {
        guard reportsScrolling, let current else { return }
        let line = topLine
        guard line != reportedTopLine else { return }
        reportedTopLine = line
        onScroll?(current.url, line, false)
    }

    private func reportCursor() {
        guard let current else { return }
        let line = line(at: textView.selectedRange().location)
        guard line != reportedCursorLine else { return }
        reportedCursorLine = line
        onCursorMove?(current.url, line)
    }

    /// The line of the character at UTF-16 offset `index`, counting from 1.
    private func line(at index: Int) -> Int {
        let starts = lineStarts()
        var low = 0
        var high = starts.count
        while low < high {
            let middle = (low + high) / 2
            if starts[middle] <= index {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }

    /// The UTF-16 offsets at which lines start, the unit of NSRange.
    private func lineStarts() -> [Int] {
        if let cachedLineStarts { return cachedLineStarts }
        var starts = [0]
        for (offset, unit) in textView.string.utf16.enumerated() where unit == 0x0A {
            starts.append(offset + 1)
        }
        cachedLineStarts = starts
        return starts
    }

    // MARK: NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        updateUnsavedChanges()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        reportCursor()
    }

    func undoManager(for view: NSTextView) -> UndoManager? {
        current?.undoManager
    }

    // MARK: NSTextStorageDelegate

    nonisolated func textStorage(
        _ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        MainActor.assumeIsolated { cachedLineStarts = nil }
    }
}

/// Calls `onScroll` whenever its clip view scrolls, for whatever reason, and makes each change
/// of its size through `aroundResize`.
private final class ScrollView: NSScrollView {
    var onScroll: (() -> Void)?
    var aroundResize: ((() -> Void) -> Void)?

    override func setFrameSize(_ newSize: NSSize) {
        guard newSize != frame.size, let aroundResize else { return super.setFrameSize(newSize) }
        aroundResize { super.setFrameSize(newSize) }
    }

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        onScroll?()
    }
}
