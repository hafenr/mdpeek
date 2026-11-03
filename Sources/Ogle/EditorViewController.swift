import AppKit
import SwiftTerm

/// The editor pane, editing the displayed document: the bundled Neovim in a terminal, with the
/// user's own configuration, or Ogle's text editor, as chosen in View › Editor.
@MainActor
final class EditorViewController: NSViewController, LocalProcessTerminalViewDelegate {
    enum Kind: String, CaseIterable {
        case neovim, text

        var title: String {
            switch self {
            case .neovim: "Neovim"
            case .text: "Text Editor"
            }
        }
    }

    private enum Session {
        case neovim(EditorTerminalView, EditorConnection)
        case text(TextEditorViewController)
    }

    /// The editor to start; one already running keeps going until stopped.
    var kind = Kind(rawValue: UserDefaults.standard.string(forKey: "editor") ?? "") ?? .neovim {
        didSet { UserDefaults.standard.set(kind.rawValue, forKey: "editor") }
    }
    private var session: Session?
    /// Holds Neovim, in neovim/, and ogle.lua.
    private let resources: URL
    /// Replaces variables of Neovim's environment.
    private let environmentOverrides: [String: String]
    private(set) var hasUnsavedChanges = false {
        didSet {
            if hasUnsavedChanges != oldValue { onUnsavedChangesChange?(hasUnsavedChanges) }
        }
    }

    /// Called with the first line the editor shows of a file, and how far through it the top is,
    /// whenever that changes, and when Ogle asks for it; the flag tells which.
    var onScroll: ((URL, Double, _ requested: Bool) -> Void)?
    /// Called with the file and line of the editor's cursor as it moves.
    var onCursorMove: ((URL, Int) -> Void)?
    /// Called when the editor gets unsaved changes, and when it no longer has any.
    var onUnsavedChangesChange: ((Bool) -> Void)?
    /// Called when Neovim quits normally.
    var onQuit: (() -> Void)?

    var focusView: NSView? {
        switch session {
        case .neovim(let terminal, _): terminal
        case .text(let editor): editor.focusView
        case nil: nil
        }
    }
    /// The text size relative to the default; it follows the preview's zoom while the two are
    /// linked.
    var zoom: CGFloat = 1 {
        didSet {
            guard zoom != oldValue else { return }
            switch session {
            case .neovim(let terminal, _): terminal.font = font
            case .text(let editor): editor.font = font
            case nil: break
            }
        }
    }
    /// At actual size, about as large as the preview's 16 px body text: the monospaced font's
    /// taller lowercase makes 15 pt read the same.
    private static let baseFontSize: CGFloat = 15
    private var font: NSFont { .monospacedSystemFont(ofSize: Self.baseFontSize * zoom, weight: .regular) }

    /// Where the editor's top is when asked to show `line` there: Neovim shows whole lines only.
    func shownLine(_ line: Double) -> Double {
        kind == .neovim ? line.rounded(.down) : line
    }

    /// Whether the running editor saves through Ogle (File › Save), rather than on its own.
    var canSave: Bool {
        if case .text = session { true } else { false }
    }
    /// How to save in the running editor.
    var saveShortcut: String { canSave ? "⌘S" : ":w" }

    init(resources: URL, environment: [String: String]) {
        self.resources = resources
        environmentOverrides = environment
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        view = NSView()
    }

    /// Shows the file at `url` in the editor, with `line` at the top if given, starting the
    /// editor if it is not running. Without a line, the editor reports where it shows the file.
    func open(_ url: URL, atLine line: Double?) {
        do {
            switch session {
            case .neovim(_, let connection): try connection.open(url, atLine: line.map { Int($0) })
            case .text(let editor): try editor.open(url, atLine: line)
            case nil:
                switch kind {
                case .neovim: try startNeovim(with: url, atLine: line.map { Int($0) })
                case .text: try startTextEditor(with: url, atLine: line)
                }
            }
        } catch {
            presentError(error)
        }
    }

    /// Scrolls the editor, if it shows the file at `url`, so that `line` is at the top.
    func scroll(_ url: URL, toLine line: Double) {
        do {
            switch session {
            case .neovim(_, let connection): try connection.scroll(url, toLine: Int(line))
            case .text(let editor): editor.scroll(url, toLine: line)
            case nil: break
            }
        } catch {
            presentError(error)
        }
    }

    func save() {
        if case .text(let editor) = session { editor.save() }
    }

    /// Ends the editor, discarding unsaved changes.
    func stop() {
        switch session {
        case .neovim(let terminal, _):
            terminal.processDelegate = nil
            terminal.terminate()
        case .text(let editor):
            editor.view.removeFromSuperview()
            editor.removeFromParent()
        case nil:
            return
        }
        end()
    }

    private func startNeovim(with url: URL, atLine line: Int?) throws {
        let connection = try EditorConnection()
        connection.onEvent = { [weak self] event in
            switch event {
            case .scroll(let path, let line, let requested): self?.onScroll?(URL(fileURLWithPath: path), Double(line), requested)
            case .cursor(let path, let line): self?.onCursorMove?(URL(fileURLWithPath: path), line)
            case .modified(let modified): self?.hasUnsavedChanges = modified
            case .background(let color):
                if case .neovim(let terminal, _) = self?.session { terminal.setBackground(color) }
            }
        }
        connection.onError = { [weak self] error in self?.presentError(error) }

        let terminal = EditorTerminalView(frame: view.bounds)
        terminal.processDelegate = self
        terminal.font = font
        terminal.configureNativeColors()
        terminal.syncColorScheme()
        // Option types the characters of the keyboard layout, and acts as Meta only on keys
        // that type none (arrows, Backspace, …).
        terminal.optionAsMetaKey = false
        terminal.optionAsMetaKeyForFunctionalKeys = true
        install(terminal)
        session = .neovim(terminal, connection)

        let shell = String(cString: getpwuid(getuid())!.pointee.pw_shell)
        let environment = Terminal.getEnvironmentVariables() + [
            "SHELL=\(shell)",
            "OGLE_NVIM=\(resources.appending(path: "neovim/bin/nvim").path)",
            "OGLE_LUA=\(resources.appending(path: "ogle.lua").path)",
            "OGLE_SOCKET=\(connection.path)",
            "OGLE_FILE=\(url.path)",
        ] + (line.map { ["OGLE_LINE=\($0)"] } ?? [])
        let overridden = Set(environmentOverrides.keys)
        let finalEnvironment = environment.filter { !overridden.contains(String($0.prefix { $0 != "=" })) }
            + environmentOverrides.map { "\($0.key)=\($0.value)" }
        // Through an interactive login shell, as in a terminal, so that Neovim and its plugins
        // find the user's tools on the PATH.
        terminal.startProcess(
            executable: shell,
            args: ["-l", "-i", "-c", #"exec "$OGLE_NVIM" --cmd 'lua dofile(vim.env.OGLE_LUA)' -- "$OGLE_FILE""#],
            environment: finalEnvironment,
            currentDirectory: url.deletingLastPathComponent().path)
    }

    private func startTextEditor(with url: URL, atLine line: Double?) throws {
        let editor = TextEditorViewController()
        editor.font = font
        editor.onScroll = { [weak self] url, line, requested in self?.onScroll?(url, line, requested) }
        editor.onCursorMove = { [weak self] url, line in self?.onCursorMove?(url, line) }
        editor.onUnsavedChangesChange = { [weak self] unsaved in self?.hasUnsavedChanges = unsaved }
        addChild(editor)
        install(editor.view)
        session = .text(editor)
        try editor.open(url, atLine: line)
    }

    /// Fills the pane below the toolbar with `content`, and lays it out at its final size. Neovim
    /// starts at that size, so it keeps the line it is asked to show at the top, rather than
    /// moving it when the terminal is resized; the text editor needs it to find lines.
    private func install(_ content: NSView) {
        view.subviews.forEach { $0.removeFromSuperview() }
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        view.layoutSubtreeIfNeeded()
    }

    private func end() {
        if case .neovim(_, let connection) = session { connection.close() }
        session = nil
        hasUnsavedChanges = false
    }

    // MARK: LocalProcessTerminalViewDelegate

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        guard case .neovim(let terminal, _) = session else { return }
        end()
        if exitCode == 0 {
            terminal.removeFromSuperview()
            onQuit?()
        } else {
            // Keeps the output, which explains what went wrong.
            let reason = exitCode.map { "exited with status \($0)" } ?? "was terminated"
            terminal.feed(text: "\r\n[Neovim \(reason)]\r\n")
        }
    }

    func processFailedToStart(source: TerminalView, error: LocalProcessError) {
        end()
        presentError(error)
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
}

private final class EditorTerminalView: LocalProcessTerminalView {
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        syncColorScheme()
    }

    /// Tells Neovim whether the system appearance is light or dark.
    func syncColorScheme() {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        updateColorScheme(isDark ? .dark : .light)
    }

    /// Uses Neovim's background (0xRRGGBB) for the margins around its grid, or the system's
    /// if Neovim has none.
    func setBackground(_ color: Int?) {
        nativeBackgroundColor = color.map {
            NSColor(
                srgbRed: CGFloat($0 >> 16 & 0xFF) / 255, green: CGFloat($0 >> 8 & 0xFF) / 255,
                blue: CGFloat($0 & 0xFF) / 255, alpha: 1)
        } ?? .textBackgroundColor
    }
}
