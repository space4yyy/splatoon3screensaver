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
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 280),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        buildUI()
        load()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        
        let isChinese = Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
        window?.title = isChinese ? "Splatoon 3 启动选项" : "Splatoon 3 Boot Options"
        
        // 1. Header label (Title)
        let titleLabel = NSTextField(labelWithString: isChinese ? "Splatoon 3 启动选项" : "Splatoon 3 Boot Options")
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // 2. Form Grid
        let grid = NSGridView()
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.rowAlignment = .firstBaseline
        grid.translatesAutoresizingMaskIntoConstraints = false
        
        // Add items to popups
        fpsPopup.addItems(withTitles: isChinese 
            ? ["30 fps", "60 fps", "120 fps", "显示器同步"]
            : ["30 fps", "60 fps", "120 fps", "Display Sync"]
        )
        scalePopup.addItems(withTitles: ["0.5x", "0.75x", "1.0x", "1.25x", "1.5x"])
        palettePopup.addItems(withTitles: isChinese
            ? ["绿 / 蓝", "红 / 蓝", "粉 / 绿", "自定义"]
            : ["Green / Blue", "Red / Blue", "Pink / Green", "Custom"]
        )
        
        // Constrain control widths
        for control in [fpsPopup, scalePopup, palettePopup, warmWell, coolWell] {
            control.translatesAutoresizingMaskIntoConstraints = false
            control.widthAnchor.constraint(equalToConstant: 160).isActive = true
        }
        
        warmWell.heightAnchor.constraint(equalToConstant: 24).isActive = true
        coolWell.heightAnchor.constraint(equalToConstant: 24).isActive = true
        
        // Add rows to grid
        grid.addRow(with: [createLabel(isChinese ? "帧率限制" : "FPS cap"), fpsPopup])
        grid.addRow(with: [createLabel(isChinese ? "渲染缩放" : "Render scale"), scalePopup])
        grid.addRow(with: [createLabel(isChinese ? "色彩方案" : "Colours"), palettePopup])
        grid.addRow(with: [createLabel(isChinese ? "暖色墨水" : "Warm ink"), warmWell])
        grid.addRow(with: [createLabel(isChinese ? "冷色墨水" : "Cool ink"), coolWell])
        
        // Align columns: Column 0 trailing (right aligned), Column 1 leading (left aligned)
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        
        // 3. Bottom Buttons
        let defaultsButton = NSButton(title: isChinese ? "恢复默认" : "Reset Defaults", target: self, action: #selector(resetDefaults))
        defaultsButton.translatesAutoresizingMaskIntoConstraints = false
        
        let doneButton = NSButton(title: isChinese ? "完成" : "Done", target: self, action: #selector(done))
        doneButton.keyEquivalent = "\r" // Enter key triggers Done
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        
        [fpsPopup, scalePopup, palettePopup, warmWell, coolWell].forEach {
            ($0 as NSControl).target = self
            ($0 as NSControl).action = #selector(changed)
        }
        
        // Assembly using a main stack view
        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.alignment = .centerX
        mainStack.spacing = 16
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(mainStack)
        
        mainStack.addArrangedSubview(titleLabel)
        mainStack.addArrangedSubview(grid)
        
        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.distribution = .equalSpacing
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(buttonRow)
        
        buttonRow.addArrangedSubview(defaultsButton)
        buttonRow.addArrangedSubview(doneButton)
        
        // Constraints
        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            mainStack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            mainStack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            
            buttonRow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            buttonRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            buttonRow.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            buttonRow.topAnchor.constraint(equalTo: mainStack.bottomAnchor, constant: 20)
        ])
    }
    
    private func createLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.alignment = .right
        return label
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
