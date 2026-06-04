import AppKit

final class ConfigSheetController: NSWindowController {
    var onChange: (() -> Void)?

    private let fpsPopup = NSPopUpButton()
    private let scalePopup = NSPopUpButton()
    private let palettePopup = NSPopUpButton()
    private let warmWell = NSColorWell()
    private let coolWell = NSColorWell()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 350),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "Splatoon 3 Boot Options"
        super.init(window: window)
        buildUI()
        load()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -24)
        ])

        fpsPopup.addItems(withTitles: ["30 fps", "60 fps", "120 fps", "Display Sync"])
        scalePopup.addItems(withTitles: ["0.5x", "0.75x", "1.0x", "1.25x", "1.5x"])
        palettePopup.addItems(withTitles: ["Green / Blue", "Red / Blue", "Pink / Green", "Custom"])

        stack.addArrangedSubview(row("FPS cap", fpsPopup))
        stack.addArrangedSubview(row("Render scale", scalePopup))
        stack.addArrangedSubview(row("Colours", palettePopup))
        stack.addArrangedSubview(row("Warm ink", warmWell))
        stack.addArrangedSubview(row("Cool ink", coolWell))

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 8
        let defaults = NSButton(title: "Reset Defaults", target: self, action: #selector(resetDefaults))
        let done = NSButton(title: "Done", target: self, action: #selector(done))
        buttons.addArrangedSubview(defaults)
        buttons.addArrangedSubview(done)
        stack.addArrangedSubview(buttons)

        [fpsPopup, scalePopup, palettePopup, warmWell, coolWell].forEach {
            ($0 as NSControl).target = self
            ($0 as NSControl).action = #selector(changed)
        }
    }

    private func row(_ label: String, _ control: NSView) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        let text = NSTextField(labelWithString: label)
        text.widthAnchor.constraint(equalToConstant: 110).isActive = true
        control.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        row.addArrangedSubview(text)
        row.addArrangedSubview(control)
        return row
    }

    private func load() {
        let s = ScreensaverSettings.load()
        fpsPopup.selectItem(at: [30, 60, 120, 0].firstIndex(of: s.fpsCap) ?? 1)
        let scales: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5]
        scalePopup.selectItem(at: scales.enumerated().min(by: { abs($0.element - s.renderScale) < abs($1.element - s.renderScale) })?.offset ?? 2)
        palettePopup.selectItem(at: max(0, min(3, s.paletteMode)))
        warmWell.color = s.customWarm
        coolWell.color = s.customCool
    }

    @objc private func changed() {
        save()
        onChange?()
    }

    @objc private func resetDefaults() {
        fpsPopup.selectItem(at: 1)
        scalePopup.selectItem(at: 2)
        palettePopup.selectItem(at: 0)
        warmWell.color = NSColor(hex: "#BAFF0A")
        coolWell.color = NSColor(hex: "#1D0AFF")
        changed()
    }

    @objc private func done() {
        save()
        window?.sheetParent?.endSheet(window!)
    }

    private func save() {
        let fpsValues = [30, 60, 120, 0]
        let scaleValues: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5]
        ScreensaverSettings(
            fpsCap: fpsValues[fpsPopup.indexOfSelectedItem],
            renderScale: scaleValues[scalePopup.indexOfSelectedItem],
            paletteMode: palettePopup.indexOfSelectedItem,
            customWarm: warmWell.color,
            customCool: coolWell.color
        ).save()
    }
}
