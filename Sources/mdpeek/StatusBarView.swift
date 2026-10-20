import AppKit

/// The strip below the document: whether the file is watched, its length, and the section
/// being read.
@MainActor
final class StatusBarView: NSView {
    private let dot = NSView()
    private let watchingLabel = NSTextField(labelWithString: "Watching for changes")
    private let statsLabel = NSTextField(labelWithString: "")
    private let sectionLabel = NSTextField(labelWithString: "")

    /// Whether a file is shown (and watched); the bar stays as an empty strip otherwise.
    var isActive = false {
        didSet {
            dot.isHidden = !isActive
            watchingLabel.isHidden = !isActive
            if !isActive {
                statsLabel.stringValue = ""
                sectionLabel.stringValue = ""
            }
        }
    }

    init() {
        super.init(frame: .zero)
        for label in [watchingLabel, statsLabel, sectionLabel] {
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            label.textColor = .secondaryLabelColor
            label.lineBreakMode = .byTruncatingTail
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        watchingLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3
        dot.setAccessibilityElement(false)

        let separator = NSBox()
        separator.boxType = .separator
        let leading = NSStackView(views: [dot, watchingLabel, statsLabel])
        leading.spacing = 6
        leading.setCustomSpacing(16, after: watchingLabel)
        for view in [separator, leading, sectionLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 24),
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),
            leading.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            leading.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 0.5),
            sectionLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leading.trailingAnchor, constant: 16),
            sectionLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            sectionLabel.centerYAnchor.constraint(equalTo: leading.centerYAnchor),
        ])
        updateDotColor()
        dot.isHidden = true
        watchingLabel.isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setWordCount(_ words: Int) {
        guard words > 0 else {
            statsLabel.stringValue = ""
            return
        }
        let minutes = max(1, Int((Double(words) / 220).rounded()))
        let count = words.formatted(.number)
        statsLabel.stringValue = "\(count) \(words == 1 ? "word" : "words") · \(minutes) min read"
    }

    func setSection(_ text: String?) {
        sectionLabel.stringValue = text ?? ""
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateDotColor()
    }

    private func updateDotColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            dot.layer?.backgroundColor = NSColor.systemGreen.cgColor
        }
    }
}
