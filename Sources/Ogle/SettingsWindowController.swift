import AppKit

/// Ogle › Settings…: which editor the editor pane runs.
@MainActor
final class SettingsWindowController: NSWindowController {
    let editorPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let mainWindow: MainWindowController

    init(mainWindow: MainWindowController) {
        self.mainWindow = mainWindow
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Settings"
        super.init(window: window)

        for kind in EditorViewController.Kind.allCases {
            editorPopUp.addItem(withTitle: kind.title)
            editorPopUp.lastItem!.representedObject = kind.rawValue
        }
        editorPopUp.target = self
        editorPopUp.action = #selector(chooseEditor(_:))
        let note = NSTextField(
            wrappingLabelWithString: "Neovim runs with your own configuration. The text editor edits as other Mac apps do.")
        note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        note.textColor = .secondaryLabelColor
        note.preferredMaxLayoutWidth = 260
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Editor:"), editorPopUp],
            [NSGridCell.emptyContentView, note],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            grid.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
        ])
        window.contentView = content
        window.setContentSize(content.fittingSize)
        window.center()
        showEditorKind()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func showWindow(_ sender: Any?) {
        showEditorKind()
        super.showWindow(sender)
    }

    @objc private func chooseEditor(_ sender: NSPopUpButton) {
        mainWindow.switchEditor(to: EditorViewController.Kind(rawValue: sender.selectedItem!.representedObject as! String)!)
        showEditorKind()
    }

    /// Selects the editor's kind, also after a switch was cancelled.
    private func showEditorKind() {
        editorPopUp.selectItem(at: editorPopUp.indexOfItem(withRepresentedObject: mainWindow.editor.kind.rawValue))
    }
}
