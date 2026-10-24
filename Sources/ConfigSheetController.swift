import AppKit

private let isChinese = Locale.preferredLanguages.first?.hasPrefix("zh") ?? false

private func localized(_ english: String, _ chinese: String) -> String {
    isChinese ? chinese : english
}

final class ConfigSheetController: NSWindowController {
    var onChange: (() -> Void)?

    private static let windowWidth: CGFloat = 480
    private static let margin: CGFloat = 20
    private static let contentWidth = windowWidth - margin * 2

    private let contentStack = NSStackView()
    private let headerSwatch = PaletteSwatchView()
    private let paletteSection = FormSection()
    private var paletteTiles: [PaletteMode: PaletteTile] = [:]
    private let paletteCaption = NSTextField(wrappingLabelWithString: "")
    private let cycleControl = NSSegmentedControl(
        labels: ScreensaverSettings.paletteCycleOptions.map { localized("\($0) s", "\($0) 秒") },
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let warmWell = NSColorWell()
    private let coolWell = NSColorWell()
    private let seedPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let fpsControl = NSSegmentedControl(
        labels: ["30", "60", "120", localized("Auto", "自动")],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let batterySwitch = NSSwitch()
    private let batteryDetail = NSTextField(wrappingLabelWithString: "")
    private var cycleRow = NSView()
    private var warmRow = NSView()
    private var coolRow = NSView()
    private var selectedPalette: PaletteMode = .random
    private var originalSettings: ScreensaverSettings?
    private var powerObserver: NSObjectProtocol?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.windowWidth, height: 480),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
        powerObserver = NotificationCenter.default.addObserver(
            forName: PowerMonitor.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshBatteryDetail()
            self?.resizeWindowToFit(animate: true)
        }
        load()
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        if let powerObserver {
            NotificationCenter.default.removeObserver(powerObserver)
        }
    }

    // MARK: - Layout

    private func buildUI() {
        guard let window, let content = window.contentView else { return }
        window.title = localized("Splatoon 3 Boot Options", "Splatoon 3 Boot 选项")

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 6
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.setHuggingPriority(.init(800), for: .vertical)
        content.addSubview(contentStack)

        let header = makeHeader()
        contentStack.addArrangedSubview(header)
        contentStack.setCustomSpacing(18, after: header)

        buildPaletteSection()
        addSection(localized("Ink Colours", "墨水配色"), paletteSection)

        seedPopup.removeAllItems()
        addSeedItem(localized("Random", "随机"), seedIndex: 0)
        seedPopup.menu?.addItem(.separator())
        for index in 1...6 {
            addSeedItem(localized("Pattern \(index)", "图案 \(index)"), seedIndex: index)
        }
        seedPopup.menu?.addItem(.separator())
        addSeedItem(localized("Procedural (original)", "程序生成（原版）"), seedIndex: 7)
        seedPopup.target = self
        seedPopup.action = #selector(controlChanged)
        seedPopup.setAccessibilityLabel(localized("Starting pattern", "初始图案"))
        let animationSection = FormSection()
        animationSection.addRow(makeRow(
            title: localized("Starting pattern", "初始图案"),
            detail: localized("The ink layout the animation starts from.", "动画开始时的墨水布局。"),
            control: seedPopup
        ))
        addSection(localized("Animation", "动画"), animationSection)

        fpsControl.target = self
        fpsControl.action = #selector(controlChanged)
        fpsControl.setAccessibilityLabel(localized("Frame rate", "帧率"))
        for segment in 0..<fpsControl.segmentCount {
            fpsControl.setWidth(50, forSegment: segment)
        }
        // System Settings forms use mini switches.
        batterySwitch.controlSize = .mini
        batterySwitch.target = self
        batterySwitch.action = #selector(controlChanged)
        batterySwitch.setAccessibilityLabel(localized("Battery saver", "电池省电"))
        let performanceSection = FormSection()
        performanceSection.addRow(makeRow(
            title: localized("Frame rate", "帧率"),
            detail: localized(
                "Auto follows the display's refresh rate. Lower rates use less power.",
                "“自动”跟随屏幕刷新率，越低越省电。"
            ),
            control: fpsControl
        ))
        performanceSection.addRow(makeRow(
            title: localized("Battery saver", "电池省电"),
            detailLabel: batteryDetail,
            control: batterySwitch
        ))
        addSection(localized("Performance", "性能与功耗"), performanceSection)

        let footer = makeFooter()
        contentStack.addArrangedSubview(footer)
        footer.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true

        // Below required so the window can animate between heights.
        let bottom = contentStack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -Self.margin)
        bottom.priority = .defaultHigh
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: content.topAnchor, constant: Self.margin),
            contentStack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: Self.margin),
            contentStack.widthAnchor.constraint(equalToConstant: Self.contentWidth),
            bottom,
        ])
    }

    private func makeHeader() -> NSView {
        headerSwatch.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            headerSwatch.widthAnchor.constraint(equalToConstant: 40),
            headerSwatch.heightAnchor.constraint(equalToConstant: 40),
        ])

        let title = NSTextField(labelWithString: "Splatoon 3 Boot")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        var subtitleText = localized("Screen Saver Options", "屏幕保护程序选项")
        if let version = Bundle(for: ConfigSheetController.self).infoDictionary?["CFBundleShortVersionString"] as? String {
            subtitleText += localized(" · Version \(version)", " · 版本 \(version)")
        }
        let subtitle = NSTextField(labelWithString: subtitleText)
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor

        let titles = NSStackView(views: [title, subtitle])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 2

        let header = NSStackView(views: [headerSwatch, titles])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12
        return header
    }

    private func buildPaletteSection() {
        let tiles = NSStackView()
        tiles.orientation = .horizontal
        tiles.distribution = .fillEqually
        tiles.spacing = 4
        for mode in PaletteMode.allCases {
            let tile = PaletteTile(title: Self.title(for: mode))
            tile.toolTip = Self.caption(for: mode)
            tile.onSelect = { [weak self] in
                self?.selectPalette(mode)
            }
            paletteTiles[mode] = tile
            tiles.addArrangedSubview(tile)
        }

        paletteCaption.font = .systemFont(ofSize: 11)
        paletteCaption.textColor = .secondaryLabelColor
        paletteCaption.alignment = .center
        paletteCaption.preferredMaxLayoutWidth = Self.contentWidth - 24

        let pickerRow = NSStackView(views: [tiles, paletteCaption])
        pickerRow.orientation = .vertical
        pickerRow.alignment = .centerX
        pickerRow.spacing = 6
        pickerRow.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 12, right: 12)
        tiles.widthAnchor.constraint(equalTo: pickerRow.widthAnchor, constant: -24).isActive = true
        paletteSection.addRow(pickerRow)

        cycleControl.target = self
        cycleControl.action = #selector(controlChanged)
        cycleControl.setAccessibilityLabel(localized("Switch every", "切换间隔"))
        for segment in 0..<cycleControl.segmentCount {
            cycleControl.setWidth(50, forSegment: segment)
        }
        cycleRow = makeRow(
            title: localized("Switch every", "切换间隔"),
            detail: localized("Then blends into the next game over 4 seconds.", "之后用 4 秒过渡到下一代。"),
            control: cycleControl
        )
        paletteSection.addRow(cycleRow)

        for (well, name) in [(warmWell, localized("Warm ink", "暖色墨水")), (coolWell, localized("Cool ink", "冷色墨水"))] {
            well.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                well.widthAnchor.constraint(equalToConstant: 52),
                well.heightAnchor.constraint(equalToConstant: 24),
            ])
            well.target = self
            well.action = #selector(customColorChanged)
            well.setAccessibilityLabel(name)
        }
        warmRow = makeRow(title: localized("Warm ink", "暖色墨水"), control: warmWell)
        coolRow = makeRow(title: localized("Cool ink", "冷色墨水"), control: coolWell)
        paletteSection.addRow(warmRow)
        paletteSection.addRow(coolRow)
    }

    private func addSection(_ title: String, _ section: FormSection) {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        contentStack.addArrangedSubview(label)
        contentStack.addArrangedSubview(section)
        section.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true
        contentStack.setCustomSpacing(18, after: section)
    }

    private func addSeedItem(_ title: String, seedIndex: Int) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.tag = seedIndex
        seedPopup.menu?.addItem(item)
    }

    private func makeRow(title: String, detail: String? = nil, detailLabel: NSTextField? = nil, control: NSView) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13)
        let labels = NSStackView(views: [titleLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2
        labels.translatesAutoresizingMaskIntoConstraints = false
        if let detailLabel = detailLabel ?? detail.map(NSTextField.init(wrappingLabelWithString:)) {
            detailLabel.font = .systemFont(ofSize: 11)
            detailLabel.textColor = .secondaryLabelColor
            detailLabel.preferredMaxLayoutWidth = Self.contentWidth - 40 - control.fittingSize.width
            labels.addArrangedSubview(detailLabel)
        }

        control.translatesAutoresizingMaskIntoConstraints = false
        let row = NSView()
        row.addSubview(labels)
        row.addSubview(control)
        let compactHeight = row.heightAnchor.constraint(equalToConstant: 40)
        compactHeight.priority = .defaultLow
        NSLayoutConstraint.activate([
            labels.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12),
            labels.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            labels.topAnchor.constraint(greaterThanOrEqualTo: row.topAnchor, constant: 10),
            control.leadingAnchor.constraint(greaterThanOrEqualTo: labels.trailingAnchor, constant: 16),
            control.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -12),
            control.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            control.topAnchor.constraint(greaterThanOrEqualTo: row.topAnchor, constant: 8),
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),
            compactHeight,
        ])
        return row
    }

    private func makeFooter() -> NSView {
        let resetButton = NSButton(title: localized("Reset to Defaults", "恢复默认"), target: self, action: #selector(resetDefaults))
        let cancelButton = NSButton(title: localized("Cancel", "取消"), target: self, action: #selector(cancel))
        cancelButton.keyEquivalent = "\u{1b}" // ESC key
        let doneButton = NSButton(title: localized("Done", "完成"), target: self, action: #selector(done))
        doneButton.keyEquivalent = "\r" // Enter key triggers Done

        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.spacing = 12
        footer.addView(resetButton, in: .leading)
        footer.addView(cancelButton, in: .trailing)
        footer.addView(doneButton, in: .trailing)
        NSLayoutConstraint.activate([
            doneButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 76),
            cancelButton.widthAnchor.constraint(equalTo: doneButton.widthAnchor),
        ])
        return footer
    }

    /// Fits the window to the visible rows, keeping the sheet's top edge fixed.
    private func resizeWindowToFit(animate: Bool) {
        guard let window else { return }
        contentStack.layoutSubtreeIfNeeded()
        let height = ceil(contentStack.fittingSize.height) + Self.margin * 2
        let size = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: Self.windowWidth, height: height)).size
        let current = window.frame
        guard abs(size.height - current.height) > 0.5 || abs(size.width - current.width) > 0.5 else { return }
        let target = NSRect(x: current.minX, y: current.maxY - size.height, width: size.width, height: size.height)
        window.setFrame(target, display: true, animate: animate && window.isVisible)
    }

    // MARK: - State

    func load() {
        let settings = ScreensaverSettings.load()
        originalSettings = settings
        apply(settings, animate: false)
    }

    private func apply(_ settings: ScreensaverSettings, animate: Bool) {
        selectedPalette = settings.paletteMode
        cycleControl.selectedSegment = ScreensaverSettings.paletteCycleOptions.firstIndex(of: settings.paletteCycleSeconds) ?? 1
        warmWell.color = settings.customWarm
        coolWell.color = settings.customCool
        seedPopup.selectItem(withTag: settings.seedIndex)
        fpsControl.selectedSegment = ScreensaverSettings.fpsOptions.firstIndex(of: settings.fpsCap) ?? 1
        batterySwitch.state = settings.batterySaver ? .on : .off
        refreshBatteryDetail()
        refreshPaletteUI(animate: animate)
    }

    private var currentSettings: ScreensaverSettings {
        ScreensaverSettings(
            fpsCap: ScreensaverSettings.fpsOptions[max(fpsControl.selectedSegment, 0)],
            batterySaver: batterySwitch.state == .on,
            paletteMode: selectedPalette,
            paletteCycleSeconds: ScreensaverSettings.paletteCycleOptions[max(cycleControl.selectedSegment, 0)],
            customWarm: warmWell.color,
            customCool: coolWell.color,
            seedIndex: seedPopup.selectedItem?.tag ?? 0
        )
    }

    private func refreshPaletteUI(animate: Bool) {
        for (mode, tile) in paletteTiles {
            tile.isSelected = mode == selectedPalette
            let swatch = swatch(for: mode)
            tile.swatch.colors = swatch.colors
            tile.swatch.badgeSymbol = swatch.badge
        }
        headerSwatch.colors = swatch(for: selectedPalette).colors
        paletteCaption.stringValue = Self.caption(for: selectedPalette)
        paletteSection.setRow(cycleRow, hidden: selectedPalette != .cycle)
        paletteSection.setRow(warmRow, hidden: selectedPalette != .custom)
        paletteSection.setRow(coolRow, hidden: selectedPalette != .custom)
        resizeWindowToFit(animate: animate)
    }

    private func refreshBatteryDetail() {
        var text = localized(
            "Runs at 30 fps on battery power or in Low Power Mode.",
            "使用电池供电或开启低电量模式时，帧率限制为 30 fps。"
        )
        if batterySwitch.state == .on && PowerMonitor.shared.prefersReducedPower {
            text += localized(" Active now.", "当前已生效。")
        }
        batteryDetail.stringValue = text
    }

    private func swatch(for mode: PaletteMode) -> (colors: [NSColor], badge: String?) {
        func inks(_ phase: Int) -> [NSColor] {
            [NSColor(linearRGB: InkPalette.warm[phase]), NSColor(linearRGB: InkPalette.cool[phase])]
        }
        let allGames = [1, 2, 0].flatMap(inks)
        switch mode {
        case .random: return (allGames, "shuffle")
        case .cycle: return (allGames, "arrow.triangle.2.circlepath")
        case .splatoon1, .splatoon2, .splatoon3: return (inks(InkPalette.phase(for: mode)), nil)
        case .custom: return ([warmWell.color, coolWell.color], "eyedropper")
        }
    }

    private static func title(for mode: PaletteMode) -> String {
        switch mode {
        case .random: return localized("Random", "随机")
        case .cycle: return localized("Cycle", "循环")
        case .splatoon1: return localized("Splatoon 1", "斯普拉遁 1")
        case .splatoon2: return localized("Splatoon 2", "斯普拉遁 2")
        case .splatoon3: return localized("Splatoon 3", "斯普拉遁 3")
        case .custom: return localized("Custom", "自定义")
        }
    }

    private static func caption(for mode: PaletteMode) -> String {
        switch mode {
        case .random: return localized("A different game's inks each time the screen saver starts.", "每次启动屏幕保护程序时，随机选用一代的配色。")
        case .cycle: return localized("Rotates through the inks of all three games.", "依次轮换三代的配色。")
        case .splatoon1: return localized("Orange vs. blue, from the original Splatoon.", "初代的橙色与蓝色。")
        case .splatoon2: return localized("Pink vs. green, from Splatoon 2.", "2 代的粉色与绿色。")
        case .splatoon3: return localized("Yellow vs. purple, from Splatoon 3.", "3 代的黄色与紫色。")
        case .custom: return localized("Pick your own pair of inks.", "自选一对墨水颜色。")
        }
    }

    // MARK: - Actions

    private func selectPalette(_ mode: PaletteMode) {
        guard mode != selectedPalette else { return }
        selectedPalette = mode
        refreshPaletteUI(animate: true)
        settingsChanged()
    }

    @objc private func customColorChanged() {
        refreshPaletteUI(animate: false)
        settingsChanged()
    }

    @objc private func controlChanged() {
        refreshBatteryDetail()
        resizeWindowToFit(animate: true)
        settingsChanged()
    }

    private func settingsChanged() {
        currentSettings.save()
        onChange?()
    }

    @objc private func resetDefaults() {
        apply(.standard, animate: true)
        settingsChanged()
    }

    @objc private func cancel() {
        if let originalSettings, ScreensaverSettings.load() != originalSettings {
            originalSettings.save()
            onChange?()
        }
        endSheet()
    }

    @objc private func done() {
        currentSettings.save()
        endSheet()
    }

    private func endSheet() {
        if warmWell.isActive || coolWell.isActive {
            warmWell.deactivate()
            coolWell.deactivate()
            NSColorPanel.shared.orderOut(nil)
        }
        guard let window = self.window else { return }
        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            window.orderOut(nil)
        }
    }
}

// MARK: - Grouped form

/// A rounded group of rows with inset separators, in the style of System Settings.
private final class FormSection: NSView {
    private let stack = NSStackView()
    private var separators: [ObjectIdentifier: NSView] = [:]

    private static let fillColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.05)
            : NSColor(white: 0, alpha: 0.035)
    }

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func addRow(_ row: NSView) {
        row.translatesAutoresizingMaskIntoConstraints = false
        if !stack.arrangedSubviews.isEmpty {
            let separator = SeparatorView()
            separator.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(separator)
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            separators[ObjectIdentifier(row)] = separator
        }
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    /// Hides a row together with the separator above it.
    func setRow(_ row: NSView, hidden: Bool) {
        row.isHidden = hidden
        separators[ObjectIdentifier(row)]?.isHidden = hidden
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        Self.fillColor.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

private final class SeparatorView: NSView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 1)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        NSRect(x: 12, y: 0, width: bounds.width - 24, height: 1).fill(using: .sourceOver)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

// MARK: - Palette picker

/// A round ink swatch: two colours are drawn as warm ink rising under cool ink,
/// like the screen saver itself; more colours are drawn as pie slices.
private final class PaletteSwatchView: NSView {
    var colors: [NSColor] = [] {
        didSet { needsDisplay = true }
    }
    var badgeSymbol: String? {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let diameter = min(bounds.width, bounds.height)
        let circle = NSRect(x: bounds.midX - diameter / 2, y: bounds.midY - diameter / 2, width: diameter, height: diameter)

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(ovalIn: circle).addClip()
        if colors.count == 2 {
            drawInkPair(warm: colors[0], cool: colors[1], in: circle)
        } else {
            drawSlices(in: circle)
        }
        NSGraphicsContext.restoreGraphicsState()

        let rim = NSBezierPath(ovalIn: circle.insetBy(dx: 0.5, dy: 0.5))
        rim.lineWidth = 1
        NSColor.black.withAlphaComponent(0.15).setStroke()
        rim.stroke()

        if let badgeSymbol {
            drawBadge(badgeSymbol, on: circle)
        }
    }

    private func drawInkPair(warm: NSColor, cool: NSColor, in rect: NSRect) {
        cool.setFill()
        rect.fill()
        let d = rect.width
        let shoreline = rect.midY - d * 0.06
        let wave = NSBezierPath()
        wave.move(to: NSPoint(x: rect.minX, y: shoreline))
        wave.curve(
            to: NSPoint(x: rect.maxX, y: shoreline),
            controlPoint1: NSPoint(x: rect.minX + d * 0.35, y: shoreline + d * 0.32),
            controlPoint2: NSPoint(x: rect.minX + d * 0.65, y: shoreline - d * 0.32)
        )
        wave.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        wave.line(to: NSPoint(x: rect.minX, y: rect.minY))
        wave.close()
        warm.setFill()
        wave.fill()
    }

    private func drawSlices(in rect: NSRect) {
        guard !colors.isEmpty else { return }
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let step = 360 / CGFloat(colors.count)
        for (index, color) in colors.enumerated() {
            let slice = NSBezierPath()
            slice.move(to: center)
            slice.appendArc(
                withCenter: center,
                radius: rect.width,
                startAngle: 90 - step * CGFloat(index),
                endAngle: 90 - step * CGFloat(index + 1),
                clockwise: true
            )
            slice.close()
            color.setFill()
            slice.fill()
        }
    }

    private func drawBadge(_ symbolName: String, on circle: NSRect) {
        let size = (circle.width * 0.44).rounded()
        let badge = NSRect(x: circle.maxX - size, y: circle.minY, width: size, height: size)
        let disc = NSBezierPath(ovalIn: badge.insetBy(dx: 0.5, dy: 0.5))
        NSColor.controlBackgroundColor.setFill()
        disc.fill()
        NSColor.separatorColor.setStroke()
        disc.lineWidth = 1
        disc.stroke()

        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size * 0.48, weight: .bold))
        else { return }
        let tinted = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            NSColor.secondaryLabelColor.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: NSRect(
            x: badge.midX - symbol.size.width / 2,
            y: badge.midY - symbol.size.height / 2,
            width: symbol.size.width,
            height: symbol.size.height
        ))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// One selectable palette: a swatch with an accent ring when selected and a
/// label underneath. Behaves as a radio button for keyboard and VoiceOver.
private final class PaletteTile: NSView {
    var onSelect: (() -> Void)?
    let swatch = PaletteSwatchView()
    private let label: NSTextField
    private var hoverArea: NSTrackingArea?
    private var isHovered = false {
        didSet { needsDisplay = true }
    }
    private var isPressed = false {
        didSet { needsDisplay = true }
    }

    var isSelected = false {
        didSet {
            // Colour only: a heavier weight would truncate names in narrow tiles.
            label.textColor = isSelected ? .labelColor : .secondaryLabelColor
            setAccessibilityValue(NSNumber(value: isSelected))
            needsDisplay = true
        }
    }

    private var ringRect: NSRect {
        swatch.frame.insetBy(dx: -4, dy: -4)
    }

    init(title: String) {
        label = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        swatch.translatesAutoresizingMaskIntoConstraints = false
        addSubview(swatch)
        addSubview(label)
        NSLayoutConstraint.activate([
            swatch.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            swatch.centerXAnchor.constraint(equalTo: centerXAnchor),
            swatch.widthAnchor.constraint(equalToConstant: 40),
            swatch.heightAnchor.constraint(equalToConstant: 40),
            label.topAnchor.constraint(equalTo: swatch.bottomAnchor, constant: 8),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(title)
        setAccessibilityValue(NSNumber(value: false))
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHovered || isPressed {
            NSColor.labelColor.withAlphaComponent(isPressed ? 0.1 : 0.05).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        }
        if isSelected {
            let ring = NSBezierPath(ovalIn: ringRect.insetBy(dx: 1.25, dy: 1.25))
            ring.lineWidth = 2.5
            NSColor.controlAccentColor.setStroke()
            ring.stroke()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    // MARK: Mouse

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea {
            removeTrackingArea(hoverArea)
        }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
    }

    override func mouseDragged(with event: NSEvent) {
        isPressed = bounds.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        if inside {
            onSelect?()
        }
    }

    // MARK: Keyboard and accessibility

    override var acceptsFirstResponder: Bool {
        NSApp.isFullKeyboardAccessEnabled
    }

    override var canBecomeKeyView: Bool {
        acceptsFirstResponder
    }

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " {
            onSelect?()
        } else {
            super.keyDown(with: event)
        }
    }

    override var focusRingMaskBounds: NSRect {
        ringRect
    }

    override func drawFocusRingMask() {
        NSBezierPath(ovalIn: ringRect).fill()
    }

    override func accessibilityPerformPress() -> Bool {
        onSelect?()
        return true
    }
}
