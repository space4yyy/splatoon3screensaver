import AppKit

final class ConfigSheetController: NSWindowController {
    var onChange: (() -> Void)?

    private let fpsPopup = NSPopUpButton()
    private let scalePopup = NSPopUpButton()
    private let palettePopup = NSPopUpButton()
    private let cyclePopup = NSPopUpButton()
    private let warmWell = NSColorWell()
    private let coolWell = NSColorWell()
    private let grid = NSGridView()
    private var originalSettings: ScreensaverSettings?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 280),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
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
        window?.title = isChinese ? "Splatoon 3 屏保选项" : "Splatoon 3 Screensaver Options"
        
        // 1. Header label (Title)
        let titleLabel = NSTextField(labelWithString: isChinese ? "Splatoon 3 屏保选项" : "Splatoon 3 Screensaver Options")
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(titleLabel)
        
        // 2. Form Grid
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.yPlacement = .center // Vertically center views in their rows (resolves NSColorWell baseline offset)
        grid.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(grid)
        
        // Add items to popups
        fpsPopup.addItems(withTitles: isChinese 
            ? ["30 fps", "60 fps", "120 fps", "显示器同步"]
            : ["30 fps", "60 fps", "120 fps", "Display Sync"]
        )
        scalePopup.addItems(withTitles: ["0.5x", "0.75x", "1.0x", "1.25x", "1.5x"])
        palettePopup.addItems(withTitles: isChinese
            ? ["历代随机", "历代循环", "斯普拉遁 1 (橙 / 蓝)", "斯普拉遁 2 (粉 / 绿)", "斯普拉遁 3 (黄 / 紫)", "自定义"]
            : ["Random on launch", "Cycle (All games)", "Splatoon 1 (Orange / Blue)", "Splatoon 2 (Pink / Green)", "Splatoon 3 (Yellow / Purple)", "Custom"]
        )
        cyclePopup.addItems(withTitles: isChinese
            ? ["30 秒", "60 秒", "90 秒", "120 秒"]
            : ["30 s", "60 s", "90 s", "120 s"]
        )
        
        // Constrain control widths
        for control in [fpsPopup, scalePopup, palettePopup, cyclePopup, warmWell, coolWell] {
            control.translatesAutoresizingMaskIntoConstraints = false
            control.widthAnchor.constraint(equalToConstant: 160).isActive = true
        }
        
        warmWell.heightAnchor.constraint(equalToConstant: 24).isActive = true
        coolWell.heightAnchor.constraint(equalToConstant: 24).isActive = true
        
        // Add rows to grid
        grid.addRow(with: [createLabel(isChinese ? "帧率限制" : "FPS cap"), fpsPopup])
        // grid.addRow(with: [createLabel(isChinese ? "渲染缩放" : "Render scale"), scalePopup]) // Hidden to protect fluid mechanics
        grid.addRow(with: [createLabel(isChinese ? "色彩方案" : "Colours"), palettePopup])
        grid.addRow(with: [createLabel(isChinese ? "循环间隔" : "Cycle interval"), cyclePopup])
        grid.addRow(with: [createLabel(isChinese ? "暖色墨水" : "Warm ink"), warmWell])
        grid.addRow(with: [createLabel(isChinese ? "冷色墨水" : "Cool ink"), coolWell])
        
        // Align columns: Column 0 trailing (right aligned), Column 1 leading (left aligned)
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        
        // 3. Bottom Buttons
        let defaultsButton = NSButton(title: isChinese ? "恢复默认" : "Reset Defaults", target: self, action: #selector(resetDefaults))
        defaultsButton.translatesAutoresizingMaskIntoConstraints = false
        
        let cancelButton = NSButton(title: isChinese ? "取消" : "Cancel", target: self, action: #selector(cancel))
        cancelButton.keyEquivalent = "\u{1b}" // ESC key
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        
        let doneButton = NSButton(title: isChinese ? "完成" : "Done", target: self, action: #selector(done))
        doneButton.keyEquivalent = "\r" // Enter key triggers Done
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        
        [fpsPopup, scalePopup, palettePopup, cyclePopup, warmWell, coolWell].forEach {
            ($0 as NSControl).target = self
            ($0 as NSControl).action = #selector(changed)
        }
        
        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.distribution = .fill
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(buttonRow)
        
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.init(100), for: .horizontal)
        spacer.setContentCompressionResistancePriority(.init(100), for: .horizontal)
        
        let rightButtonStack = NSStackView()
        rightButtonStack.orientation = .horizontal
        rightButtonStack.spacing = 12
        rightButtonStack.translatesAutoresizingMaskIntoConstraints = false
        rightButtonStack.addArrangedSubview(cancelButton)
        rightButtonStack.addArrangedSubview(doneButton)
        
        buttonRow.addArrangedSubview(defaultsButton)
        buttonRow.addArrangedSubview(spacer)
        buttonRow.addArrangedSubview(rightButtonStack)
        
        let bottomConstraint = buttonRow.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)
        bottomConstraint.priority = .init(950) // Allow slight variance during window resize to prevent autolayout warnings

        // Constraints (Bypassing mainStack stretching to center grid perfectly as a unit)
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            
            grid.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            grid.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            
            buttonRow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            buttonRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            bottomConstraint,
            buttonRow.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 20)
        ])
    }
    
    private func createLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.alignment = .right
        return label
    }

    private func updateColorWellsVisibility(animate: Bool) {
        guard let window = window else { return }
        let isCustom = palettePopup.indexOfSelectedItem == 5 // Index 5 is "Custom"
        let isCycle = palettePopup.indexOfSelectedItem == 1 // Index 1 is "Cycle (All games)"
        
        // Hide/show palette-specific rows.
        grid.row(at: 2).isHidden = !isCycle
        grid.row(at: 3).isHidden = !isCustom
        grid.row(at: 4).isHidden = !isCustom
        
        let targetContentHeight: CGFloat = 178 + (isCycle ? 34 : 0) + (isCustom ? 68 : 0)
        let currentFrame = window.frame
        let targetFrame = window.frameRect(forContentRect: NSRect(x: currentFrame.origin.x, y: currentFrame.origin.y, width: currentFrame.size.width, height: targetContentHeight))
        
        let diff = targetFrame.size.height - currentFrame.size.height
        var finalFrame = targetFrame
        finalFrame.origin.y = currentFrame.origin.y - diff
        
        window.setFrame(finalFrame, display: true, animate: animate)
    }

    func load() {
        let s = ScreensaverSettings.load()
        originalSettings = s
        fpsPopup.selectItem(at: [30, 60, 120, 0].firstIndex(of: s.fpsCap) ?? 1)
        let scales: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5]
        scalePopup.selectItem(at: scales.enumerated().min(by: { abs($0.element - s.renderScale) < abs($1.element - s.renderScale) })?.offset ?? 2)
        palettePopup.selectItem(at: max(0, min(5, s.paletteMode)))
        cyclePopup.selectItem(at: [30, 60, 90, 120].firstIndex(of: s.paletteCycleSeconds) ?? 1)
        warmWell.color = s.customWarm
        coolWell.color = s.customCool
        updateColorWellsVisibility(animate: false)
    }

    @objc private func changed() {
        save()
        updateColorWellsVisibility(animate: true)
        onChange?()
    }

    @objc private func resetDefaults() {
        fpsPopup.selectItem(at: 1)
        scalePopup.selectItem(at: 2)
        palettePopup.selectItem(at: 0)
        cyclePopup.selectItem(at: 1)
        warmWell.color = NSColor(hex: "#BAFF0A")
        coolWell.color = NSColor(hex: "#1D0AFF")
        changed()
    }

    @objc private func cancel() {
        if let originalSettings, ScreensaverSettings.load() != originalSettings {
            originalSettings.save()
            onChange?()
        }
        endSheet()
    }

    @objc private func done() {
        save()
        endSheet()
    }

    private func endSheet() {
        guard let window = self.window else { return }
        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            window.orderOut(nil)
        }
    }

    private func save() {
        let fpsValues = [30, 60, 120, 0]
        let scaleValues: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5]
        let cycleValues = [30, 60, 90, 120]
        ScreensaverSettings(
            fpsCap: fpsValues[fpsPopup.indexOfSelectedItem],
            renderScale: scaleValues[scalePopup.indexOfSelectedItem],
            paletteMode: palettePopup.indexOfSelectedItem,
            paletteCycleSeconds: cycleValues[cyclePopup.indexOfSelectedItem],
            customWarm: warmWell.color,
            customCool: coolWell.color
        ).save()
    }
}
