import AppKit

final class PreviewGridItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("PreviewGridItem")
    let thumbnail = NSImageView()
    let name = NSTextField(wrappingLabelWithString: "")
    let subtitle = NSTextField(labelWithString: "")
    let plate = NSBox()
    var representedEntry: Entry?
    var doubleClick: ((Entry) -> Void)?
    override func loadView() {
        view = NSView()
        plate.boxType = .custom; plate.borderWidth = 0; plate.borderColor = .clear; plate.cornerRadius = 8
        plate.fillColor = .labelColor.withAlphaComponent(0.025)
        thumbnail.imageScaling = .scaleProportionallyUpOrDown
        thumbnail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        thumbnail.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        name.alignment = .center; name.maximumNumberOfLines = 2; name.lineBreakMode = .byTruncatingMiddle
        subtitle.alignment = .center; subtitle.textColor = .systemBlue; subtitle.font = .systemFont(ofSize: 11)
        name.wantsLayer = true; name.layer?.cornerRadius = 4; name.layer?.masksToBounds = true
        for child in [plate, thumbnail, name, subtitle] { child.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(child) }
        NSLayoutConstraint.activate([
            plate.topAnchor.constraint(equalTo: view.topAnchor, constant: 4), plate.centerXAnchor.constraint(equalTo: view.centerXAnchor), plate.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -24), plate.heightAnchor.constraint(equalTo: plate.widthAnchor),
            thumbnail.leadingAnchor.constraint(equalTo: plate.leadingAnchor, constant: 6), thumbnail.trailingAnchor.constraint(equalTo: plate.trailingAnchor, constant: -6), thumbnail.topAnchor.constraint(equalTo: plate.topAnchor, constant: 6), thumbnail.bottomAnchor.constraint(equalTo: plate.bottomAnchor, constant: -6),
            name.topAnchor.constraint(equalTo: plate.bottomAnchor, constant: 5), name.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 2), name.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -2), name.heightAnchor.constraint(lessThanOrEqualToConstant: 48),
            subtitle.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 2), subtitle.leadingAnchor.constraint(equalTo: view.leadingAnchor), subtitle.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        let recognizer = NSClickGestureRecognizer(target: self, action: #selector(openFolder)); recognizer.numberOfClicksRequired = 2
        view.addGestureRecognizer(recognizer)
    }
    override func viewDidLayout() { super.viewDidLayout(); name.preferredMaxLayoutWidth = max(20, view.bounds.width - 4) }
    override var isSelected: Bool { didSet { updateSelection() } }
    override func prepareForReuse() { super.prepareForReuse(); representedEntry = nil; thumbnail.image = nil; doubleClick = nil }
    func configure(entry: Entry, title: String, detail: String, image: NSImage, font: CGFloat) {
        _ = view; representedEntry = entry; name.stringValue = title; subtitle.stringValue = detail; thumbnail.image = image
        name.font = .systemFont(ofSize: font); subtitle.font = .systemFont(ofSize: max(10, font - 1))
        view.setAccessibilityElement(true); view.setAccessibilityLabel(title + ", " + detail)
        name.toolTip = entry.name
        updateSelection()
    }
    private func updateSelection() {
        guard isViewLoaded else { return }
        name.layer?.backgroundColor = isSelected ? NSColor.selectedContentBackgroundColor.cgColor : NSColor.clear.cgColor
        name.textColor = isSelected ? .alternateSelectedControlTextColor : .labelColor
        plate.fillColor = isSelected ? .labelColor.withAlphaComponent(0.08) : .labelColor.withAlphaComponent(0.025)
    }
    @objc private func openFolder() { if let representedEntry { doubleClick?(representedEntry) } }
}
