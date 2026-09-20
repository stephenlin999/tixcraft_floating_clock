import AppKit
import Carbon.HIToolbox
import Foundation
import UserNotifications

private let tixcraftURL = URL(string: "https://tixcraft.com/activity")!
private let taipeiTimeZone = TimeZone(identifier: "Asia/Taipei")!

private func isTrustedTixcraftURL(_ url: URL?) -> Bool {
    guard let url,
          url.scheme?.caseInsensitiveCompare("https") == .orderedSame,
          let host = url.host else {
        return false
    }
    return host.caseInsensitiveCompare(tixcraftURL.host!) == .orderedSame
}

private func makeFormatter(_ format: String, timeZone: TimeZone) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    formatter.dateFormat = format
    return formatter
}

private let httpDateFormatter = makeFormatter(
    "EEE',' dd MMM yyyy HH':'mm':'ss zzz",
    timeZone: TimeZone(secondsFromGMT: 0)!
)

private func formatCountdownInterval(_ interval: TimeInterval, showHundredths: Bool) -> String {
    let remaining = max(0, interval)
    let wholeSeconds = Int(remaining)
    let days = wholeSeconds / 86_400
    let hours = (wholeSeconds % 86_400) / 3_600
    let minutes = (wholeSeconds % 3_600) / 60
    let seconds = wholeSeconds % 60

    if days > 0 {
        return String(format: "%dd %02d:%02d:%02d", days, hours, minutes, seconds)
    }
    if showHundredths {
        let hundredths = Int((remaining - Double(wholeSeconds)) * 100)
        return String(format: "%02d:%02d:%02d.%02d", hours, minutes, seconds, hundredths)
    }
    return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
}

private func formatMenuCountdown(_ interval: TimeInterval) -> String {
    let seconds = max(0, Int(interval))
    if seconds >= 86_400 {
        return String(format: "%dd %02dh", seconds / 86_400, (seconds % 86_400) / 3_600)
    }
    if seconds >= 3_600 {
        return String(format: "%d:%02d:%02d", seconds / 3_600, (seconds % 3_600) / 60, seconds % 60)
    }
    return String(format: "%02d:%02d", seconds / 60, seconds % 60)
}

private func parseCountdownTarget(_ input: String, now: Date) -> Date? {
    let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return nil }

    if value.hasPrefix("@") {
        let time = String(value.dropFirst()).replacingOccurrences(of: " ", with: "")
        let calendar = Calendar(identifier: .gregorian)
        for format in ["H:mm:ss", "H:mm", "ha", "h:mma"] {
            let formatter = makeFormatter(format, timeZone: taipeiTimeZone)
            guard let parsed = formatter.date(from: time.lowercased()) else { continue }
            let components = calendar.dateComponents(in: taipeiTimeZone, from: parsed)
            var targetComponents = calendar.dateComponents(in: taipeiTimeZone, from: now)
            targetComponents.hour = components.hour
            targetComponents.minute = components.minute
            targetComponents.second = components.second ?? 0
            targetComponents.nanosecond = 0
            guard var target = calendar.date(from: targetComponents) else { continue }
            if target <= now {
                target = calendar.date(byAdding: .day, value: 1, to: target)!
            }
            return target
        }
        return nil
    }

    for format in ["yyyy/MM/dd HH:mm:ss", "yyyy/MM/dd HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm"] {
        let formatter = makeFormatter(format, timeZone: taipeiTimeZone)
        if let target = formatter.date(from: value), target > now, target.timeIntervalSince1970 <= 4_102_444_800 {
            return target
        }
    }

    let scanner = Scanner(string: value.lowercased())
    scanner.charactersToBeSkipped = .whitespaces
    var duration: TimeInterval = 0
    var foundComponent = false
    while !scanner.isAtEnd {
        guard let number = scanner.scanDouble(), number.isFinite, number > 0,
              let unit = scanner.scanCharacters(from: .letters) else {
            return nil
        }
        let scale: TimeInterval
        switch unit {
        case "s", "sec", "secs", "second", "seconds": scale = 1
        case "m", "min", "mins", "minute", "minutes": scale = 60
        case "h", "hr", "hrs", "hour", "hours": scale = 3_600
        case "d", "day", "days": scale = 86_400
        default: return nil
        }
        duration += number * scale
        foundComponent = true
    }
    guard foundComponent, duration >= 1, duration <= 31_536_000 else { return nil }
    return now.addingTimeInterval(duration)
}

private enum DisplayMode: String {
    case clock
    case countdown
}

private enum Preferences {
    private static let alwaysOnTopKey = "alwaysOnTop"
    private static let showHundredthsKey = "showHundredths"
    private static let syncIntervalKey = "syncInterval"
    private static let compactModeKey = "compactMode"
    private static let lockPositionKey = "lockPosition"
    private static let clickThroughKey = "clickThrough"
    private static let backgroundOpacityKey = "backgroundOpacity"
    private static let displayModeKey = "displayMode"
    private static let countdownDateKey = "countdownDate"
    private static let countdownActiveKey = "countdownActive"
    private static let countdownLabelKey = "countdownLabel"
    private static let countdownAlertsKey = "countdownAlerts"
    private static let dualTimeKey = "dualTime"
    private static let keepAwakeKey = "keepAwake"
    private static let keepDisplayAwakeKey = "keepDisplayAwake"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            alwaysOnTopKey: true,
            showHundredthsKey: true,
            syncIntervalKey: 15.0,
            compactModeKey: false,
            lockPositionKey: false,
            clickThroughKey: false,
            backgroundOpacityKey: 0.88,
            displayModeKey: DisplayMode.clock.rawValue,
            countdownDateKey: Date().addingTimeInterval(3600).timeIntervalSince1970,
            countdownActiveKey: true,
            countdownLabelKey: "",
            countdownAlertsKey: false,
            dualTimeKey: true,
            keepAwakeKey: false,
            keepDisplayAwakeKey: false
        ])
    }

    static var alwaysOnTop: Bool {
        get { UserDefaults.standard.bool(forKey: alwaysOnTopKey) }
        set { UserDefaults.standard.set(newValue, forKey: alwaysOnTopKey) }
    }

    static var showHundredths: Bool {
        get { UserDefaults.standard.bool(forKey: showHundredthsKey) }
        set { UserDefaults.standard.set(newValue, forKey: showHundredthsKey) }
    }

    static var syncInterval: TimeInterval {
        get { UserDefaults.standard.double(forKey: syncIntervalKey) }
        set { UserDefaults.standard.set(newValue, forKey: syncIntervalKey) }
    }

    static var compactMode: Bool {
        get { UserDefaults.standard.bool(forKey: compactModeKey) }
        set { UserDefaults.standard.set(newValue, forKey: compactModeKey) }
    }

    static var lockPosition: Bool {
        get { UserDefaults.standard.bool(forKey: lockPositionKey) }
        set { UserDefaults.standard.set(newValue, forKey: lockPositionKey) }
    }

    static var clickThrough: Bool {
        get { UserDefaults.standard.bool(forKey: clickThroughKey) }
        set { UserDefaults.standard.set(newValue, forKey: clickThroughKey) }
    }

    static var backgroundOpacity: CGFloat {
        get { CGFloat(UserDefaults.standard.double(forKey: backgroundOpacityKey)) }
        set { UserDefaults.standard.set(Double(newValue), forKey: backgroundOpacityKey) }
    }

    static var displayMode: DisplayMode {
        get { DisplayMode(rawValue: UserDefaults.standard.string(forKey: displayModeKey) ?? "") ?? .clock }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: displayModeKey) }
    }

    static var countdownDate: Date {
        get { Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: countdownDateKey)) }
        set { UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: countdownDateKey) }
    }

    static var countdownActive: Bool {
        get { UserDefaults.standard.bool(forKey: countdownActiveKey) }
        set { UserDefaults.standard.set(newValue, forKey: countdownActiveKey) }
    }

    static var countdownLabel: String {
        get { UserDefaults.standard.string(forKey: countdownLabelKey) ?? "" }
        set { UserDefaults.standard.set(String(newValue.prefix(80)), forKey: countdownLabelKey) }
    }

    static var countdownAlerts: Bool {
        get { UserDefaults.standard.bool(forKey: countdownAlertsKey) }
        set { UserDefaults.standard.set(newValue, forKey: countdownAlertsKey) }
    }

    static var dualTime: Bool {
        get { UserDefaults.standard.bool(forKey: dualTimeKey) }
        set { UserDefaults.standard.set(newValue, forKey: dualTimeKey) }
    }

    static var keepAwake: Bool {
        get { UserDefaults.standard.bool(forKey: keepAwakeKey) }
        set { UserDefaults.standard.set(newValue, forKey: keepAwakeKey) }
    }

    static var keepDisplayAwake: Bool {
        get { UserDefaults.standard.bool(forKey: keepDisplayAwakeKey) }
        set { UserDefaults.standard.set(newValue, forKey: keepDisplayAwakeKey) }
    }
}

private final class SettingsWindowController: NSObject {
    let window: NSWindow
    var onChange: ((Bool) -> Void)?

    private let alwaysOnTopButton = NSButton(
        checkboxWithTitle: "Keep the clock above other windows",
        target: nil,
        action: nil
    )
    private let showHundredthsButton = NSButton(
        checkboxWithTitle: "Show hundredths of a second",
        target: nil,
        action: nil
    )
    private let compactModeButton = NSButton(
        checkboxWithTitle: "Compact mode",
        target: nil,
        action: nil
    )
    private let lockPositionButton = NSButton(
        checkboxWithTitle: "Lock position and size",
        target: nil,
        action: nil
    )
    private let clickThroughButton = NSButton(
        checkboxWithTitle: "Allow clicks to pass through the clock",
        target: nil,
        action: nil
    )
    private let intervalPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let modeControl = NSSegmentedControl(
        labels: ["Clock", "Countdown"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let countdownPicker = NSDatePicker()
    private let countdownLabelField = NSTextField(string: "")
    private let countdownAlertsButton = NSButton(
        checkboxWithTitle: "Alert 1 minute, 10 seconds, and at the target",
        target: nil,
        action: nil
    )
    private let notificationStatusLabel = NSTextField(labelWithString: "Notification permission: checking…")
    private let dualTimeButton = NSButton(
        checkboxWithTitle: "Show current time with the countdown",
        target: nil,
        action: nil
    )
    private let keepAwakeButton = NSButton(
        checkboxWithTitle: "Prevent idle sleep until the target",
        target: nil,
        action: nil
    )
    private let keepDisplayAwakeButton = NSButton(
        checkboxWithTitle: "Also keep the display awake",
        target: nil,
        action: nil
    )
    private let opacitySlider = NSSlider(value: 88, minValue: 35, maxValue: 100, target: nil, action: nil)
    private let opacityValueLabel = NSTextField(labelWithString: "88%")

    override init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 470, height: 540),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.title = "Tixcraft Time Settings"
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("TixcraftTimeSettingsWindow")

        [15, 30, 60].forEach { seconds in
            intervalPopup.addItem(withTitle: "\(seconds) seconds")
            intervalPopup.lastItem?.tag = seconds
        }

        countdownPicker.datePickerStyle = .textFieldAndStepper
        countdownPicker.datePickerMode = .single
        countdownPicker.datePickerElements = [.yearMonthDay, .hourMinuteSecond]
        countdownPicker.timeZone = taipeiTimeZone
        countdownLabelField.placeholderString = "Optional countdown label"
        countdownLabelField.widthAnchor.constraint(equalToConstant: 250).isActive = true
        opacityValueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        notificationStatusLabel.textColor = .secondaryLabelColor

        [
            alwaysOnTopButton,
            showHundredthsButton,
            compactModeButton,
            lockPositionButton,
            clickThroughButton,
            intervalPopup,
            modeControl,
            countdownPicker,
            countdownLabelField,
            countdownAlertsButton,
            dualTimeButton,
            keepAwakeButton,
            keepDisplayAwakeButton,
            opacitySlider
        ].forEach {
            $0.target = self
            $0.action = #selector(settingChanged)
        }

        let intervalLabel = NSTextField(labelWithString: "Synchronization interval")
        let intervalRow = NSStackView(views: [intervalLabel, intervalPopup])
        intervalRow.orientation = .horizontal
        intervalRow.spacing = 16

        let modeRow = NSStackView(views: [
            NSTextField(labelWithString: "Display"),
            modeControl
        ])
        modeRow.orientation = .horizontal
        modeRow.spacing = 16

        let countdownRow = NSStackView(views: [
            NSTextField(labelWithString: "Countdown target"),
            countdownPicker
        ])
        countdownRow.orientation = .horizontal
        countdownRow.spacing = 16

        let countdownLabelRow = NSStackView(views: [
            NSTextField(labelWithString: "Countdown label"),
            countdownLabelField
        ])
        countdownLabelRow.orientation = .horizontal
        countdownLabelRow.spacing = 16

        let opacityRow = NSStackView(views: [
            NSTextField(labelWithString: "Background opacity"),
            opacitySlider,
            opacityValueLabel
        ])
        opacityRow.orientation = .horizontal
        opacityRow.spacing = 12
        opacitySlider.widthAnchor.constraint(equalToConstant: 150).isActive = true

        let stack = NSStackView(views: [
            alwaysOnTopButton,
            showHundredthsButton,
            compactModeButton,
            lockPositionButton,
            clickThroughButton,
            opacityRow,
            intervalRow,
            modeRow,
            countdownRow,
            countdownLabelRow,
            countdownAlertsButton,
            notificationStatusLabel,
            dualTimeButton,
            keepAwakeButton,
            keepDisplayAwakeButton
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16

        let content = NSView()
        content.addSubview(stack)
        window.contentView = content
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24)
        ])
    }

    func show() {
        reload()
        if window.frameAutosaveName.isEmpty || !window.setFrameUsingName("TixcraftTimeSettingsWindow") {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func reload() {
        alwaysOnTopButton.state = Preferences.alwaysOnTop ? .on : .off
        showHundredthsButton.state = Preferences.showHundredths ? .on : .off
        compactModeButton.state = Preferences.compactMode ? .on : .off
        lockPositionButton.state = Preferences.lockPosition ? .on : .off
        clickThroughButton.state = Preferences.clickThrough ? .on : .off
        intervalPopup.selectItem(withTag: Int(Preferences.syncInterval))
        modeControl.selectedSegment = Preferences.displayMode == .clock ? 0 : 1
        countdownPicker.dateValue = Preferences.countdownDate
        countdownLabelField.stringValue = Preferences.countdownLabel
        countdownAlertsButton.state = Preferences.countdownAlerts ? .on : .off
        dualTimeButton.state = Preferences.dualTime ? .on : .off
        keepAwakeButton.state = Preferences.keepAwake ? .on : .off
        keepDisplayAwakeButton.state = Preferences.keepDisplayAwake ? .on : .off
        keepDisplayAwakeButton.isEnabled = Preferences.keepAwake
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let status: String
            switch settings.authorizationStatus {
            case .authorized, .provisional: status = "allowed"
            case .denied: status = "denied in System Settings"
            case .notDetermined: status = "not requested"
            @unknown default: status = "unavailable"
            }
            DispatchQueue.main.async {
                self?.notificationStatusLabel.stringValue = "Notification permission: \(status)"
            }
        }
        opacitySlider.doubleValue = Double(Preferences.backgroundOpacity * 100)
        opacityValueLabel.stringValue = "\(Int(opacitySlider.doubleValue.rounded()))%"
    }

    @objc private func settingChanged() {
        let shouldRequestNotifications = !Preferences.countdownAlerts && countdownAlertsButton.state == .on
        Preferences.alwaysOnTop = alwaysOnTopButton.state == .on
        Preferences.showHundredths = showHundredthsButton.state == .on
        Preferences.compactMode = compactModeButton.state == .on
        Preferences.lockPosition = lockPositionButton.state == .on
        Preferences.clickThrough = clickThroughButton.state == .on
        Preferences.backgroundOpacity = CGFloat(opacitySlider.doubleValue / 100)
        Preferences.displayMode = modeControl.selectedSegment == 1 ? .countdown : .clock
        Preferences.countdownDate = countdownPicker.dateValue
        if Preferences.displayMode == .countdown {
            Preferences.countdownActive = true
        }
        Preferences.countdownLabel = countdownLabelField.stringValue
        Preferences.countdownAlerts = countdownAlertsButton.state == .on
        Preferences.dualTime = dualTimeButton.state == .on
        Preferences.keepAwake = keepAwakeButton.state == .on
        Preferences.keepDisplayAwake = Preferences.keepAwake && keepDisplayAwakeButton.state == .on
        keepDisplayAwakeButton.isEnabled = Preferences.keepAwake
        opacityValueLabel.stringValue = "\(Int(opacitySlider.doubleValue.rounded()))%"
        if let seconds = intervalPopup.selectedItem?.tag {
            Preferences.syncInterval = TimeInterval(seconds)
        }
        onChange?(shouldRequestNotifications)
    }
}

private final class CountdownWindowController: NSObject, NSTextFieldDelegate {
    let window: NSWindow
    var onSave: ((Date, String, Bool, Bool, Bool) -> Void)?

    private let targetField = NSTextField(string: "")
    private let labelField = NSTextField(string: "")
    private let resolvedLabel = NSTextField(labelWithString: "")
    private let alertsButton = NSButton(checkboxWithTitle: "Enable advance and target alerts", target: nil, action: nil)
    private let notificationStatusLabel = NSTextField(labelWithString: "Notification permission: checking…")
    private let keepAwakeButton = NSButton(checkboxWithTitle: "Prevent idle sleep until target", target: nil, action: nil)
    private let keepDisplayAwakeButton = NSButton(checkboxWithTitle: "Also keep display awake", target: nil, action: nil)
    private let saveButton = NSButton(title: "Set Countdown", target: nil, action: nil)
    private var referenceDate = Date()
    private var referenceUptime = ProcessInfo.processInfo.systemUptime
    private var resolvedTarget: Date?

    override init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 390),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.title = "Set Countdown"
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("TixcraftTimeCountdownWindow")

        targetField.placeholderString = "5m, 1h30m, @12:00, or 2026/09/20 12:00"
        targetField.delegate = self
        labelField.placeholderString = "Optional label"

        let presets = NSSegmentedControl(
            labels: ["+5m", "+10m", "+30m", "+1h"],
            trackingMode: .momentary,
            target: self,
            action: #selector(selectPreset)
        )
        presets.segmentStyle = .rounded

        resolvedLabel.textColor = .secondaryLabelColor
        resolvedLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        notificationStatusLabel.textColor = .secondaryLabelColor

        keepAwakeButton.target = self
        keepAwakeButton.action = #selector(keepAwakeChanged)
        keepDisplayAwakeButton.target = self
        keepDisplayAwakeButton.action = #selector(refreshResolution)
        alertsButton.target = self
        alertsButton.action = #selector(refreshResolution)

        saveButton.target = self
        saveButton.action = #selector(save)
        saveButton.keyEquivalent = "\r"
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.keyEquivalent = "\u{1b}"

        let buttons = NSStackView(views: [cancelButton, saveButton])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.alignment = .centerY

        let stack = NSStackView(views: [
            NSTextField(labelWithString: "Target"),
            targetField,
            presets,
            resolvedLabel,
            NSTextField(labelWithString: "Label"),
            labelField,
            alertsButton,
            notificationStatusLabel,
            keepAwakeButton,
            keepDisplayAwakeButton,
            buttons
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        targetField.widthAnchor.constraint(equalToConstant: 440).isActive = true
        labelField.widthAnchor.constraint(equalToConstant: 440).isActive = true

        let content = NSView()
        content.addSubview(stack)
        window.contentView = content
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 22)
        ])
    }

    func show(referenceDate: Date) {
        self.referenceDate = referenceDate
        referenceUptime = ProcessInfo.processInfo.systemUptime
        targetField.stringValue = ""
        labelField.stringValue = Preferences.countdownLabel
        alertsButton.state = Preferences.countdownAlerts ? .on : .off
        keepAwakeButton.state = Preferences.keepAwake ? .on : .off
        keepDisplayAwakeButton.state = Preferences.keepDisplayAwake ? .on : .off
        keepDisplayAwakeButton.isEnabled = Preferences.keepAwake
        updateNotificationStatus()
        refreshResolution()
        if !window.setFrameUsingName("TixcraftTimeCountdownWindow") {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(targetField)
        NSApp.activate(ignoringOtherApps: true)
    }

    func controlTextDidChange(_ obj: Notification) {
        refreshResolution()
    }

    @objc private func selectPreset(_ sender: NSSegmentedControl) {
        let values = ["5m", "10m", "30m", "1h"]
        guard values.indices.contains(sender.selectedSegment) else { return }
        targetField.stringValue = values[sender.selectedSegment]
        refreshResolution()
    }

    @objc private func keepAwakeChanged() {
        keepDisplayAwakeButton.isEnabled = keepAwakeButton.state == .on
        if keepAwakeButton.state == .off {
            keepDisplayAwakeButton.state = .off
        }
        refreshResolution()
    }

    @objc private func refreshResolution() {
        resolvedTarget = parseCountdownTarget(targetField.stringValue, now: currentReferenceDate())
        saveButton.isEnabled = resolvedTarget != nil
        if let target = resolvedTarget {
            let formatter = makeFormatter("yyyy/MM/dd HH:mm:ss 'Asia/Taipei'", timeZone: taipeiTimeZone)
            resolvedLabel.stringValue = "Resolves to \(formatter.string(from: target))"
            resolvedLabel.textColor = .secondaryLabelColor
        } else {
            resolvedLabel.stringValue = "Enter a future duration, clock time, or date."
            resolvedLabel.textColor = .systemRed
        }
    }

    @objc private func save() {
        guard let target = parseCountdownTarget(targetField.stringValue, now: currentReferenceDate()) else { return }
        onSave?(
            target,
            String(labelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)),
            alertsButton.state == .on,
            keepAwakeButton.state == .on,
            keepAwakeButton.state == .on && keepDisplayAwakeButton.state == .on
        )
        window.orderOut(nil)
    }

    @objc private func cancel() {
        window.orderOut(nil)
    }

    private func updateNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let status: String
            switch settings.authorizationStatus {
            case .authorized, .provisional: status = "allowed"
            case .denied: status = "denied in System Settings"
            case .notDetermined: status = "will be requested when enabled"
            @unknown default: status = "unavailable"
            }
            DispatchQueue.main.async {
                self?.notificationStatusLabel.stringValue = "Notification permission: \(status)"
            }
        }
    }

    private func currentReferenceDate() -> Date {
        referenceDate.addingTimeInterval(ProcessInfo.processInfo.systemUptime - referenceUptime)
    }
}

private final class CountdownAlerts: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let identifiers = ["countdown-60", "countdown-10", "countdown-0"]
    private var targetEpoch: TimeInterval?
    private var passedThresholds: Set<Int> = []
    private var generation = 0

    func start() {
        center.delegate = self
    }

    func configure(
        target: Date,
        label: String,
        remaining: TimeInterval,
        enabled: Bool,
        requestPermission: Bool
    ) {
        generation += 1
        let currentGeneration = generation
        if targetEpoch != target.timeIntervalSince1970 {
            targetEpoch = target.timeIntervalSince1970
            passedThresholds.removeAll()
        }

        [60, 10, 0].filter { remaining <= TimeInterval($0) }.forEach {
            passedThresholds.insert($0)
        }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        guard enabled, remaining > 0 else { return }

        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            if settings.authorizationStatus == .notDetermined && requestPermission {
                self.center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    guard granted else { return }
                    self.schedule(
                        target: target,
                        label: label,
                        remaining: remaining,
                        generation: currentGeneration
                    )
                }
            } else if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
                self.schedule(target: target, label: label, remaining: remaining, generation: currentGeneration)
            }
        }
    }

    func cancel() {
        generation += 1
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private func schedule(target: Date, label: String, remaining: TimeInterval, generation: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  generation == self.generation,
                  target.timeIntervalSince1970 == self.targetEpoch else { return }

            let name = label.isEmpty ? "Countdown" : label
            for threshold in [60, 10, 0] where !self.passedThresholds.contains(threshold) {
                let delay = remaining - TimeInterval(threshold)
                guard delay >= 1 else { continue }

                let content = UNMutableNotificationContent()
                content.title = "Tixcraft Time"
                switch threshold {
                case 60: content.body = "\(name) reaches its target in 1 minute."
                case 10: content.body = "\(name) reaches its target in 10 seconds."
                default: content.body = "\(name) target reached."
                }
                content.sound = .default
                let request = UNNotificationRequest(
                    identifier: "countdown-\(threshold)",
                    content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
                )
                self.center.add(request)
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

private final class ClickThroughButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class MetricsCapturingDelegate: NSObject, URLSessionTaskDelegate {
    private let onTTFB: (TimeInterval?) -> Void
    private var fired = false

    init(onTTFB: @escaping (TimeInterval?) -> Void) {
        self.onTTFB = onTTFB
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard isTrustedTixcraftURL(request.url) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting taskMetrics: URLSessionTaskMetrics) {
        guard !fired else { return }
        fired = true
        if let transaction = taskMetrics.transactionMetrics.last,
           let requestEnd = transaction.requestEndDate,
           let responseStart = transaction.responseStartDate {
            onTTFB(responseStart.timeIntervalSince(requestEnd))
        } else {
            onTTFB(nil)
        }
    }
}

private struct MetricsSnapshot {
    var rttMedian: TimeInterval?
    var rttJitter: TimeInterval?
    var ttfb: TimeInterval?
    var vbeMillis: Double?
}

private enum TimeSource: String {
    case xTimer = "X-Timer"
    case httpDate = "HTTP Date"
}

private final class FloatingTimeView: NSView {
    let titleLabel = NSTextField(labelWithString: "TIXCRAFT")
    let timeLabel = NSTextField(labelWithString: "--:--:--.--")
    let dateLabel = NSTextField(labelWithString: "syncing...")
    let statusLabel = NSTextField(labelWithString: "connecting")
    let metricsLabel = NSTextField(labelWithString: "RTT --  TTFB --  VBE --")
    let syncButton = ClickThroughButton(title: "Sync", target: nil, action: nil)
    let closeButton = ClickThroughButton(title: "x", target: nil, action: nil)
    private var regularConstraints: [NSLayoutConstraint] = []
    private var compactConstraints: [NSLayoutConstraint] = []
    private var trackingArea: NSTrackingArea?
    private var isCompact = false
    private var isHovering = false
    private var statusText = "connecting"
    private var statusColor = NSColor.systemYellow

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = NSColor(calibratedWhite: 0.07, alpha: 0.88).cgColor
        layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.12).cgColor
        layer?.borderWidth = 1

        [titleLabel, timeLabel, dateLabel, statusLabel, metricsLabel, syncButton, closeButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = NSColor(calibratedRed: 0.70, green: 0.86, blue: 1.0, alpha: 1)

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 32, weight: .semibold)
        timeLabel.textColor = .white
        timeLabel.alignment = .center
        timeLabel.cell?.lineBreakMode = .byClipping

        dateLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        dateLabel.textColor = NSColor(calibratedWhite: 0.83, alpha: 1)
        dateLabel.cell?.lineBreakMode = .byTruncatingTail
        dateLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        statusLabel.textColor = NSColor(calibratedRed: 0.55, green: 0.95, blue: 0.67, alpha: 1)

        metricsLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        metricsLabel.textColor = NSColor(calibratedWhite: 0.62, alpha: 1)

        [syncButton, closeButton].forEach {
            $0.isBordered = false
            $0.font = .systemFont(ofSize: 12, weight: .semibold)
            $0.contentTintColor = NSColor(calibratedWhite: 0.88, alpha: 1)
        }
        syncButton.toolTip = "Synchronize now"
        closeButton.toolTip = "Quit Tixcraft Time"

        regularConstraints = [
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),

            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 24),

            syncButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -2),
            syncButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            syncButton.widthAnchor.constraint(equalToConstant: 42),

            timeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            timeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            timeLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),

            dateLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 17),
            dateLabel.topAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: 0),

            statusLabel.leadingAnchor.constraint(equalTo: dateLabel.trailingAnchor, constant: 10),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            statusLabel.centerYAnchor.constraint(equalTo: dateLabel.centerYAnchor),

            metricsLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 17),
            metricsLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            metricsLabel.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: 4)
        ]
        compactConstraints = [
            timeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            timeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            timeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            closeButton.widthAnchor.constraint(equalToConstant: 24),

            syncButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -2),
            syncButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            syncButton.widthAnchor.constraint(equalToConstant: 42),

            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            statusLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            statusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 12)
        ]
        NSLayoutConstraint.activate(regularConstraints)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateCompactControls()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateCompactControls()
    }

    func setCompact(_ compact: Bool) {
        guard compact != isCompact else {
            updateCompactControls()
            return
        }
        isCompact = compact
        NSLayoutConstraint.deactivate(compact ? regularConstraints : compactConstraints)
        NSLayoutConstraint.activate(compact ? compactConstraints : regularConstraints)
        [titleLabel, dateLabel, metricsLabel].forEach { $0.isHidden = compact }
        statusLabel.isHidden = false
        renderStatus()
        updateCompactControls()
        needsLayout = true
    }

    func setBackgroundOpacity(_ opacity: CGFloat) {
        layer?.backgroundColor = NSColor(
            calibratedWhite: 0.07,
            alpha: min(max(opacity, 0.35), 1)
        ).cgColor
    }

    func applyScale(for width: CGFloat) {
        let baseWidth: CGFloat = isCompact ? 240 : 286
        let scale = min(max(width / baseWidth, 0.8), 1.8)
        let baseSize: CGFloat = timeLabel.stringValue == "TARGET REACHED" ? 22 : (isCompact ? 30 : 32)
        timeLabel.font = .monospacedDigitSystemFont(
            ofSize: baseSize * scale,
            weight: .semibold
        )
    }

    func setTime(_ text: String) {
        guard timeLabel.stringValue != text else { return }
        timeLabel.stringValue = text
        applyScale(for: bounds.width)
    }

    func setStatus(_ text: String, color: NSColor) {
        guard statusText != text || statusColor != color else { return }
        statusText = text
        statusColor = color
        renderStatus()
    }

    private func renderStatus() {
        statusLabel.stringValue = isCompact ? "●" : statusText
        statusLabel.textColor = statusColor
        statusLabel.toolTip = statusText
        statusLabel.setAccessibilityLabel(statusText)
    }

    private func updateCompactControls() {
        let hideControls = isCompact && !isHovering
        syncButton.isHidden = hideControls
        closeButton.isHidden = hideControls
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class FloatingWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class GlobalHotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init?(action: @escaping () -> Void) {
        self.action = action
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        guard InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                Unmanaged<GlobalHotKey>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                    .action()
                return noErr
            },
            1,
            &eventType,
            pointer,
            &handler
        ) == noErr else {
            return nil
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x54495843), id: 1)
        guard RegisterEventHotKey(
            UInt32(kVK_ANSI_T),
            UInt32(cmdKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKey
        ) == noErr else {
            if let handler { RemoveEventHandler(handler) }
            return nil
        }
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}

private final class TixcraftClock {
    private struct ParsedTime {
        let date: Date
        let source: TimeSource
    }

    private struct ServerSample {
        let serverDate: Date
        let source: TimeSource
        let midpoint: TimeInterval
        let roundTrip: TimeInterval
        let ttfb: TimeInterval?
        let vbeMillis: Double?
    }

    private var anchor: (date: Date, uptime: TimeInterval)?
    private(set) var lastSync: Date?
    private(set) var source: TimeSource?
    private var isSyncing = false
    private let shutdownLock = NSLock()
    private var shutdownRequested = false

    private var rttSamples: [TimeInterval] = []
    private var lastTTFB: TimeInterval?
    private var lastVBE: Double?

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 2
        config.timeoutIntervalForRequest = 2
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    private var isShutDown: Bool {
        shutdownLock.lock()
        defer { shutdownLock.unlock() }
        return shutdownRequested
    }

    func shutdown() {
        shutdownLock.lock()
        let shouldCancel = !shutdownRequested
        shutdownRequested = true
        shutdownLock.unlock()

        guard shouldCancel else { return }
        session.invalidateAndCancel()
    }

    func currentServerDate() -> Date? {
        guard let anchor else { return nil }
        return anchor.date.addingTimeInterval(ProcessInfo.processInfo.systemUptime - anchor.uptime)
    }

    func currentMetrics() -> MetricsSnapshot {
        var snap = MetricsSnapshot()
        snap.ttfb = lastTTFB
        snap.vbeMillis = lastVBE
        if !rttSamples.isEmpty {
            let sorted = rttSamples.sorted()
            snap.rttMedian = sorted[sorted.count / 2]
            let mean = rttSamples.reduce(0, +) / Double(rttSamples.count)
            let variance = rttSamples.reduce(0) { $0 + pow($1 - mean, 2) } / Double(rttSamples.count)
            snap.rttJitter = sqrt(variance)
        }
        return snap
    }

    func sync(completion: @escaping (String) -> Void) {
        guard !isShutDown else { return }
        guard !isSyncing else {
            completion("syncing")
            return
        }
        isSyncing = true
        collectBoundarySample(previous: nil, deadline: ProcessInfo.processInfo.systemUptime + 2.2, completion: completion)
    }

    private func recordMetrics(_ sample: ServerSample) {
        rttSamples.append(sample.roundTrip)
        if rttSamples.count > 10 {
            rttSamples.removeFirst()
        }
        if let ttfb = sample.ttfb {
            lastTTFB = ttfb
        }
        if let vbe = sample.vbeMillis {
            lastVBE = vbe
        }
    }

    private func finishSync(
        anchor: (date: Date, uptime: TimeInterval)? = nil,
        source: TimeSource? = nil,
        status: String,
        completion: @escaping (String) -> Void
    ) {
        guard !isShutDown else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isShutDown else { return }
            if let anchor {
                self.anchor = anchor
                self.lastSync = Date()
                self.source = source
            }
            self.isSyncing = false
            completion(status)
        }
    }

    private func collectBoundarySample(
        previous: ServerSample?,
        deadline: TimeInterval,
        completion: @escaping (String) -> Void
    ) {
        guard !isShutDown else { return }
        fetchSample { [weak self] sample in
            guard let self, !self.isShutDown else { return }
            guard let sample else {
                self.finishSync(
                    status: "sync failed",
                    completion: completion
                )
                return
            }

            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isShutDown else { return }
                self.recordMetrics(sample)
            }

            if let previous, sample.serverDate > previous.serverDate {
                let boundaryUptime = previous.midpoint + (sample.midpoint - previous.midpoint) / 2
                self.finishSync(
                    anchor: (sample.serverDate, boundaryUptime),
                    source: sample.source,
                    status: "edge sync",
                    completion: completion
                )
                return
            }

            if ProcessInfo.processInfo.systemUptime >= deadline {
                self.finishSync(
                    anchor: (sample.serverDate, sample.midpoint),
                    source: sample.source,
                    status: "sec sync",
                    completion: completion
                )
                return
            }

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.05) {
                guard !self.isShutDown else { return }
                self.collectBoundarySample(previous: sample, deadline: deadline, completion: completion)
            }
        }
    }

    private func fetchSample(completion: @escaping (ServerSample?) -> Void) {
        guard !isShutDown else { return }
        var request = URLRequest(url: tixcraftURL)
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 2
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("Mozilla/5.0 TixcraftTime/1.1", forHTTPHeaderField: "User-Agent")

        let started = ProcessInfo.processInfo.systemUptime
        let lock = NSLock()
        var capturedTTFB: TimeInterval?
        var ended: TimeInterval = started
        var capturedResponse: HTTPURLResponse?

        let group = DispatchGroup()
        group.enter()
        group.enter()

        let delegate = MetricsCapturingDelegate { ttfb in
            lock.lock()
            capturedTTFB = ttfb
            lock.unlock()
            group.leave()
        }

        let task = session.dataTask(with: request) { _, response, error in
            lock.lock()
            ended = ProcessInfo.processInfo.systemUptime
            capturedResponse = error == nil ? response as? HTTPURLResponse : nil
            lock.unlock()
            group.leave()
        }
        task.delegate = delegate
        task.resume()

        group.notify(queue: DispatchQueue.global(qos: .utility)) { [weak self] in
            guard let self, !self.isShutDown else { return }
            guard let http = capturedResponse,
                  isTrustedTixcraftURL(http.url),
                  let parsed = Self.parseHighPrecisionTime(from: http) else {
                completion(nil)
                return
            }
            let vbe = http.value(forHTTPHeaderField: "X-Timer")
                .flatMap(Self.parseVBE)
            let midpoint = started + max(0, ended - started) / 2
            completion(ServerSample(
                serverDate: parsed.date,
                source: parsed.source,
                midpoint: midpoint,
                roundTrip: ended - started,
                ttfb: capturedTTFB,
                vbeMillis: vbe
            ))
        }
    }

    private static func parseHighPrecisionTime(from response: HTTPURLResponse) -> ParsedTime? {
        if let xTimer = response.value(forHTTPHeaderField: "X-Timer"),
           let startEpoch = parseXTimerValue(xTimer, prefix: "S"),
           (946_684_800...4_102_444_800).contains(startEpoch) {
            return ParsedTime(date: Date(timeIntervalSince1970: startEpoch), source: .xTimer)
        }

        if let dateValue = response.value(forHTTPHeaderField: "Date"),
           let date = httpDateFormatter.date(from: dateValue),
           (946_684_800...4_102_444_800).contains(date.timeIntervalSince1970) {
            return ParsedTime(date: date, source: .httpDate)
        }

        return nil
    }

    private static func parseXTimerValue(_ string: String, prefix: String) -> Double? {
        for part in string.split(separator: ",") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(prefix),
               let value = Double(trimmed.dropFirst(prefix.count)),
               value.isFinite {
                return value
            }
        }
        return nil
    }

    private static func parseVBE(_ string: String) -> Double? {
        parseXTimerValue(string, prefix: "VBE").flatMap { $0 >= 0 ? $0 : nil }
    }

#if SELF_TEST
    static func runSelfTests() {
        precondition(parseXTimerValue("S1700000000.25,VS0,VE1", prefix: "S") == 1_700_000_000.25)
        precondition(parseXTimerValue("SNaN,VS0,VE1", prefix: "S") == nil)
        precondition(parseXTimerValue("SInfinity", prefix: "S") == nil)
        precondition(parseVBE("VBE12.5") == 12.5)
        precondition(parseVBE("VBE-1") == nil)
        precondition(formatCountdownInterval(90_061, showHundredths: false) == "1d 01:01:01")
        precondition(formatCountdownInterval(3_661.5, showHundredths: true) == "01:01:01.50")
        precondition(formatCountdownInterval(-1, showHundredths: false) == "00:00:00")
        precondition(formatMenuCountdown(65) == "01:05")
        precondition(formatMenuCountdown(3_661) == "1:01:01")
        precondition(isTrustedTixcraftURL(tixcraftURL))
        precondition(!isTrustedTixcraftURL(URL(string: "https://example.com/activity")))
        precondition(!isTrustedTixcraftURL(URL(string: "http://tixcraft.com/activity")))

        let targetFormatter = makeFormatter("yyyy/MM/dd HH:mm:ss", timeZone: taipeiTimeZone)
        let targetNow = targetFormatter.date(from: "2026/09/20 11:00:00")!
        precondition(parseCountdownTarget("5m", now: targetNow)?.timeIntervalSince(targetNow) == 300)
        precondition(parseCountdownTarget("1h30m", now: targetNow)?.timeIntervalSince(targetNow) == 5_400)
        precondition(targetFormatter.string(from: parseCountdownTarget("@12:00", now: targetNow)!) == "2026/09/20 12:00:00")
        precondition(targetFormatter.string(from: parseCountdownTarget("@10:00", now: targetNow)!) == "2026/09/21 10:00:00")
        precondition(parseCountdownTarget("tomorrow", now: targetNow) == nil)

        let validDate = Date(timeIntervalSince1970: 1_700_000_000)
        let dateHeader = httpDateFormatter.string(from: validDate)
        let validResponse = HTTPURLResponse(
            url: tixcraftURL,
            statusCode: 403,
            httpVersion: nil,
            headerFields: ["X-Timer": "S1700000000.25,VE12.5"]
        )!
        precondition(parseHighPrecisionTime(from: validResponse)?.source == .xTimer)

        let fallbackResponse = HTTPURLResponse(
            url: tixcraftURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["X-Timer": "S999", "Date": dateHeader]
        )!
        precondition(parseHighPrecisionTime(from: fallbackResponse)?.source == .httpDate)
        print("Self-tests passed")
    }
#endif
}

private final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let view = FloatingTimeView(frame: NSRect(x: 0, y: 0, width: 286, height: 132))
    private let clock = TixcraftClock()
    private let countdownAlerts = CountdownAlerts()
    private var window: NSWindow!
    private var displayTimer: Timer?
    private var syncTimer: Timer?
    private var statusItem: NSStatusItem?
    private var globalHotKey: GlobalHotKey?
    private var settingsWindowController: SettingsWindowController?
    private var countdownWindowController: CountdownWindowController?
    private var keepAwakeActivity: NSObjectProtocol?
    private var keepAwakeTimer: Timer?
    private var keepAwakeOptions: ProcessInfo.ActivityOptions = []
    private var clockVisibilityItems: [NSMenuItem] = []
    private var alwaysOnTopItems: [NSMenuItem] = []
    private var compactModeItems: [NSMenuItem] = []
    private var lockPositionItems: [NSMenuItem] = []
    private var clickThroughItems: [NSMenuItem] = []
    private var displayModeItems: [NSMenuItem] = []
    private var keepAwakeItems: [NSMenuItem] = []
    private var appliedCompactMode: Bool?
    private var isSnapping = false
    private var syncState = "connecting"

    private let hundredthsFormatter = makeFormatter("HH:mm:ss.SS", timeZone: taipeiTimeZone)
    private let secondsFormatter = makeFormatter("HH:mm:ss", timeZone: taipeiTimeZone)
    private let dateFormatter = makeFormatter("yyyy/MM/dd", timeZone: taipeiTimeZone)
    private let countdownDateFormatter = makeFormatter("yyyy/MM/dd HH:mm:ss", timeZone: taipeiTimeZone)
    private let countdownShortFormatter = makeFormatter("MM/dd HH:mm:ss", timeZone: taipeiTimeZone)

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        stopClockActivity()
        stopKeepAwake()
        countdownAlerts.cancel()
        clock.shutdown()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()
        countdownAlerts.start()
        NSApp.setActivationPolicy(.regular)
        NSApp.mainMenu = makeMainMenu()
        configureWindow()
        configureStatusItem()
        globalHotKey = GlobalHotKey { [weak self] in
            DispatchQueue.main.async {
                self?.toggleClockWindow()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(wakeFromSleep),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        applyPreferences()
        showClock()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        showClock()
        return true
    }

    func applicationDidHide(_ notification: Notification) {
        stopClockActivity()
        updateMenuState()
    }

    func applicationDidUnhide(_ notification: Notification) {
        if window.isVisible {
            startClockActivity(syncImmediately: false)
        }
    }

    private func configureWindow() {
        let size = view.frame.size
        let targetScreen = preferredScreen()
        let screenFrame = targetScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(x: screenFrame.maxX - size.width - 28, y: screenFrame.maxY - size.height - 28)
        let frameName = "TixcraftFloatingClockWindow"
        let initialFrame = targetScreen.flatMap(storedFrame(for:)) ?? NSRect(origin: origin, size: size)

        window = FloatingWindow(
            contentRect: initialFrame,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.delegate = self
        window.contentView = view
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.setFrameAutosaveName(frameName)
        if targetScreen.flatMap(storedFrame(for:)) == nil && window.setFrameUsingName(frameName) {
            constrainWindow(to: targetScreen)
        }

        view.closeButton.target = self
        view.closeButton.action = #selector(close)
        view.syncButton.target = self
        view.syncButton.action = #selector(forceSync)
        view.menu = makeClockContextMenu()
        view.setAccessibilityLabel("Tixcraft floating clock")
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "TixcraftTimeStatusItem"
        item.isVisible = true
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "clock", accessibilityDescription: "Tixcraft Time")
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            button.toolTip = "Tixcraft Time"
            button.setAccessibilityLabel("Tixcraft Time")
        }

        let menu = NSMenu(title: "Tixcraft Time")
        menu.addItem(makeVisibilityMenuItem())
        menu.addItem(menuItem("Sync Now", action: #selector(forceSync)))
        menu.addItem(menuItem("Set Countdown…", action: #selector(showCountdownSetup)))
        menu.addItem(menuItem("Cancel Countdown", action: #selector(cancelCountdown)))
        addClockControls(to: menu)
        menu.addItem(menuItem("Settings…", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit Tixcraft Time", action: #selector(quit), keyEquivalent: "q"))

        item.menu = menu
        statusItem = item
        updateMenuState()
    }

    private func makeClockContextMenu() -> NSMenu {
        let menu = NSMenu(title: "Clock Controls")
        menu.addItem(menuItem("Sync Now", action: #selector(forceSync)))
        menu.addItem(menuItem("Set Countdown…", action: #selector(showCountdownSetup)))
        menu.addItem(menuItem("Cancel Countdown", action: #selector(cancelCountdown)))
        addClockControls(to: menu)
        menu.addItem(menuItem("Settings…", action: #selector(showSettings)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit Tixcraft Time", action: #selector(quit)))
        return menu
    }

    private func addClockControls(to menu: NSMenu) {
        menu.addItem(.separator())

        let displayMode = menuItem("Show Countdown", action: #selector(toggleDisplayMode))
        displayModeItems.append(displayMode)
        menu.addItem(displayMode)

        let compactMode = menuItem("Compact Mode", action: #selector(toggleCompactMode))
        compactModeItems.append(compactMode)
        menu.addItem(compactMode)

        let alwaysOnTop = menuItem("Always on Top", action: #selector(toggleAlwaysOnTop))
        alwaysOnTopItems.append(alwaysOnTop)
        menu.addItem(alwaysOnTop)

        let lockPosition = menuItem("Lock Position and Size", action: #selector(toggleLockPosition))
        lockPositionItems.append(lockPosition)
        menu.addItem(lockPosition)

        let clickThrough = menuItem("Click Through", action: #selector(toggleClickThrough))
        clickThroughItems.append(clickThrough)
        menu.addItem(clickThrough)

        let keepAwake = menuItem("Keep Awake Until Target", action: #selector(toggleKeepAwake))
        keepAwakeItems.append(keepAwake)
        menu.addItem(keepAwake)

        menu.addItem(menuItem("Move to Current Screen", action: #selector(moveToCurrentScreen)))
        menu.addItem(.separator())
    }

    private func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "Tixcraft Time")
        let aboutItem = NSMenuItem(
            title: "About Tixcraft Time",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = NSApp
        appMenu.addItem(aboutItem)
        appMenu.addItem(.separator())
        appMenu.addItem(menuItem("Set Countdown…", action: #selector(showCountdownSetup)))
        appMenu.addItem(menuItem("Cancel Countdown", action: #selector(cancelCountdown)))
        appMenu.addItem(menuItem("Settings…", action: #selector(showSettings), keyEquivalent: ","))
        appMenu.addItem(.separator())

        let hideItem = NSMenuItem(
            title: "Hide Tixcraft Time",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        hideItem.target = NSApp
        appMenu.addItem(hideItem)
        appMenu.addItem(.separator())

        let quitItem = menuItem("Quit Tixcraft Time", action: #selector(quit), keyEquivalent: "q")
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        let visibilityItem = makeVisibilityMenuItem()
        visibilityItem.keyEquivalent = "t"
        visibilityItem.keyEquivalentModifierMask = [.command, .option]
        windowMenu.addItem(visibilityItem)
        addClockControls(to: windowMenu)
        windowMenu.addItem(menuItem("Settings…", action: #selector(showSettings), keyEquivalent: ","))
        windowMenu.addItem(.separator())
        let arrangeItem = NSMenuItem(
            title: "Bring All to Front",
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        )
        arrangeItem.target = NSApp
        windowMenu.addItem(arrangeItem)
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu

        return mainMenu
    }

    private func menuItem(
        _ title: String,
        action: Selector,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func makeVisibilityMenuItem() -> NSMenuItem {
        let item = menuItem("Hide Clock", action: #selector(toggleClockWindow))
        clockVisibilityItems.append(item)
        return item
    }

    private func updateMenuState() {
        let isVisible = window?.isVisible == true
        let title = isVisible ? "Hide Clock" : "Show Clock"
        clockVisibilityItems.forEach { $0.title = title }
        alwaysOnTopItems.forEach { $0.state = Preferences.alwaysOnTop ? .on : .off }
        compactModeItems.forEach { $0.state = Preferences.compactMode ? .on : .off }
        lockPositionItems.forEach { $0.state = Preferences.lockPosition ? .on : .off }
        clickThroughItems.forEach { $0.state = Preferences.clickThrough ? .on : .off }
        keepAwakeItems.forEach {
            $0.state = keepAwakeActivity == nil ? .off : .on
            $0.isEnabled = Preferences.countdownActive
        }
        displayModeItems.forEach {
            $0.title = Preferences.displayMode == .clock ? "Show Countdown" : "Show Clock"
        }
        updateStatusItem(serverDate: clock.currentServerDate())
    }

    private func updateStatusItem(serverDate: Date?) {
        guard let button = statusItem?.button else { return }
        if window?.isVisible != true {
            let title = Preferences.countdownActive ? " Paused" : ""
            let toolTip = Preferences.countdownActive
                ? "Clock updates are paused; scheduled countdown alerts remain active."
                : "Tixcraft Time"
            if button.title != title { button.title = title }
            if button.toolTip != toolTip { button.toolTip = toolTip }
            return
        }
        guard Preferences.displayMode == .countdown,
              Preferences.countdownActive,
              let serverDate else {
            if !button.title.isEmpty { button.title = "" }
            if button.toolTip != "Tixcraft Time" { button.toolTip = "Tixcraft Time" }
            return
        }
        let remaining = Preferences.countdownDate.timeIntervalSince(serverDate)
        let title = remaining <= 0 ? " Done" : " \(formatMenuCountdown(remaining))"
        let toolTip = Preferences.countdownLabel.isEmpty
            ? "Tixcraft Time countdown"
            : Preferences.countdownLabel
        if button.title != title { button.title = title }
        if button.toolTip != toolTip { button.toolTip = toolTip }
        button.setAccessibilityLabel(toolTip)
    }

    private func startClockActivity(syncImmediately: Bool) {
        guard window.isVisible else { return }
        scheduleDisplayTimer()
        scheduleSyncTimer()
        refreshDisplay()
        if syncImmediately {
            forceSync()
        }
    }

    private func stopClockActivity() {
        displayTimer?.invalidate()
        displayTimer = nil
        syncTimer?.invalidate()
        syncTimer = nil
    }

    private func scheduleDisplayTimer() {
        displayTimer?.invalidate()
        let interval = Preferences.showHundredths ? 1.0 / 60.0 : 0.1
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.refreshDisplay()
        }
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }

    private func scheduleSyncTimer() {
        syncTimer?.invalidate()
        let timer = Timer(timeInterval: max(15, Preferences.syncInterval), repeats: true) { [weak self] _ in
            self?.syncQuietly()
        }
        RunLoop.main.add(timer, forMode: .common)
        syncTimer = timer
    }

    private func countdownTitle() -> String {
        guard Preferences.displayMode == .countdown else { return "TIXCRAFT" }
        let label = Preferences.countdownLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? "COUNTDOWN" : String(label.uppercased().prefix(28))
    }

    private func configureCountdownServices(requestNotifications: Bool = false) {
        guard Preferences.countdownActive,
              let serverDate = clock.currentServerDate(),
              let lastSync = clock.lastSync,
              Date().timeIntervalSince(lastSync) <= max(Preferences.syncInterval * 3, 60) else {
            countdownAlerts.cancel()
            stopKeepAwake()
            return
        }
        let remaining = Preferences.countdownDate.timeIntervalSince(serverDate)
        countdownAlerts.configure(
            target: Preferences.countdownDate,
            label: Preferences.countdownLabel,
            remaining: remaining,
            enabled: Preferences.countdownAlerts,
            requestPermission: requestNotifications
        )

        guard Preferences.keepAwake, remaining > 0 else {
            stopKeepAwake()
            return
        }
        var options: ProcessInfo.ActivityOptions = [.userInitiated, .idleSystemSleepDisabled]
        if Preferences.keepDisplayAwake {
            options.insert(.idleDisplaySleepDisabled)
        }
        if keepAwakeActivity == nil || options != keepAwakeOptions {
            stopKeepAwake()
            keepAwakeOptions = options
            keepAwakeActivity = ProcessInfo.processInfo.beginActivity(
                options: options,
                reason: "Active Tixcraft Time countdown"
            )
        }
        keepAwakeTimer?.invalidate()
        let timer = Timer(timeInterval: remaining, repeats: false) { [weak self] _ in
            self?.stopKeepAwake()
            self?.refreshDisplay()
        }
        RunLoop.main.add(timer, forMode: .common)
        keepAwakeTimer = timer
    }

    private func stopKeepAwake() {
        keepAwakeTimer?.invalidate()
        keepAwakeTimer = nil
        if let activity = keepAwakeActivity {
            ProcessInfo.processInfo.endActivity(activity)
            keepAwakeActivity = nil
        }
        keepAwakeOptions = []
    }

    private func applyPreferences(requestNotifications: Bool = false) {
        window?.level = Preferences.alwaysOnTop ? .floating : .normal
        window?.isMovable = !Preferences.lockPosition
        window?.isMovableByWindowBackground = !Preferences.lockPosition
        window?.ignoresMouseEvents = Preferences.clickThrough
        if Preferences.lockPosition {
            window?.styleMask.remove(.resizable)
        } else {
            window?.styleMask.insert(.resizable)
        }
        applyWindowMode()
        view.setBackgroundOpacity(Preferences.backgroundOpacity)
        view.titleLabel.stringValue = countdownTitle()
        settingsWindowController?.reload()
        configureCountdownServices(requestNotifications: requestNotifications)
        updateMenuState()
        if window?.isVisible == true {
            scheduleDisplayTimer()
            scheduleSyncTimer()
            refreshDisplay()
        }
    }

    private func applyWindowMode() {
        let compact = Preferences.compactMode
        view.setCompact(compact)

        let aspect = compact ? NSSize(width: 240, height: 64) : NSSize(width: 286, height: 132)
        window.contentAspectRatio = aspect
        window.contentMinSize = compact
            ? NSSize(width: 190, height: 51)
            : NSSize(width: 230, height: 106)
        window.contentMaxSize = compact
            ? NSSize(width: 480, height: 128)
            : NSSize(width: 572, height: 264)

        if appliedCompactMode != compact {
            let top = window.frame.maxY
            let width = min(max(window.frame.width, window.contentMinSize.width), window.contentMaxSize.width)
            let size = NSSize(width: width, height: width * aspect.height / aspect.width)
            window.setContentSize(size)
            window.setFrameOrigin(NSPoint(x: window.frame.minX, y: top - window.frame.height))
            appliedCompactMode = compact
        }
        view.applyScale(for: window.contentView?.bounds.width ?? window.frame.width)
    }

    @objc private func toggleClockWindow(_ sender: Any? = nil) {
        if window.isVisible {
            hideClock()
        } else {
            showClock()
        }
    }

    private func showClock() {
        NSApp.unhide(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        startClockActivity(syncImmediately: true)
        updateMenuState()
    }

    private func hideClock() {
        window.orderOut(nil)
        stopClockActivity()
        updateMenuState()
    }

    @objc private func showSettings(_ sender: Any? = nil) {
        if settingsWindowController == nil {
            let controller = SettingsWindowController()
            controller.onChange = { [weak self] requestNotifications in
                self?.applyPreferences(requestNotifications: requestNotifications)
            }
            settingsWindowController = controller
        }
        settingsWindowController?.show()
    }

    @objc private func toggleAlwaysOnTop(_ sender: Any? = nil) {
        Preferences.alwaysOnTop.toggle()
        applyPreferences()
    }

    @objc private func toggleCompactMode(_ sender: Any? = nil) {
        Preferences.compactMode.toggle()
        applyPreferences()
    }

    @objc private func toggleLockPosition(_ sender: Any? = nil) {
        Preferences.lockPosition.toggle()
        applyPreferences()
    }

    @objc private func toggleClickThrough(_ sender: Any? = nil) {
        Preferences.clickThrough.toggle()
        applyPreferences()
    }

    @objc private func toggleKeepAwake(_ sender: Any? = nil) {
        Preferences.keepAwake.toggle()
        if !Preferences.keepAwake {
            Preferences.keepDisplayAwake = false
        }
        applyPreferences()
    }

    @objc private func toggleDisplayMode(_ sender: Any? = nil) {
        Preferences.displayMode = Preferences.displayMode == .clock ? .countdown : .clock
        applyPreferences()
    }

    @objc private func showCountdownSetup(_ sender: Any? = nil) {
        if countdownWindowController == nil {
            let controller = CountdownWindowController()
            controller.onSave = { [weak self] target, label, alerts, keepAwake, keepDisplayAwake in
                let shouldRequestNotifications = alerts && !Preferences.countdownAlerts
                Preferences.countdownDate = target
                Preferences.countdownLabel = label
                Preferences.countdownAlerts = alerts
                Preferences.keepAwake = keepAwake
                Preferences.keepDisplayAwake = keepDisplayAwake
                Preferences.countdownActive = true
                Preferences.displayMode = .countdown
                self?.applyPreferences(requestNotifications: shouldRequestNotifications)
                self?.showClock()
            }
            countdownWindowController = controller
        }
        countdownWindowController?.show(referenceDate: clock.currentServerDate() ?? Date())
    }

    @objc private func cancelCountdown(_ sender: Any? = nil) {
        Preferences.countdownActive = false
        Preferences.displayMode = .clock
        countdownAlerts.cancel()
        stopKeepAwake()
        applyPreferences()
    }

    @objc private func moveToCurrentScreen(_ sender: Any? = nil) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        if let screen, let saved = storedFrame(for: screen) {
            window.setFrame(window.constrainFrameRect(saved, to: screen), display: true)
        } else {
            let origin = NSPoint(
                x: visibleFrame.maxX - window.frame.width - 12,
                y: visibleFrame.maxY - window.frame.height - 12
            )
            window.setFrameOrigin(origin)
        }
        showClock()
    }

    private func preferredScreen() -> NSScreen? {
        NSScreen.screens.max {
            $0.visibleFrame.width * $0.visibleFrame.height < $1.visibleFrame.width * $1.visibleFrame.height
        } ?? NSScreen.main
    }

    private func screenStorageKey(_ screen: NSScreen) -> String {
        let width = Int(screen.frame.width * screen.backingScaleFactor)
        let height = Int(screen.frame.height * screen.backingScaleFactor)
        return "TixcraftClockFrame.\(screen.localizedName).\(width)x\(height)"
    }

    private func storedFrame(for screen: NSScreen) -> NSRect? {
        guard let value = UserDefaults.standard.string(forKey: screenStorageKey(screen)) else { return nil }
        let frame = NSRectFromString(value)
        return frame.width > 0 && frame.height > 0 ? frame : nil
    }

    private func saveFrame(for screen: NSScreen) {
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: screenStorageKey(screen))
    }

    private func constrainWindow(to screen: NSScreen?) {
        guard let screen else { return }
        window.setFrame(window.constrainFrameRect(window.frame, to: screen), display: false)
    }

    @objc private func screenParametersChanged(_ notification: Notification) {
        guard window != nil, let screen = preferredScreen() else { return }
        if let saved = storedFrame(for: screen) {
            window.setFrame(window.constrainFrameRect(saved, to: screen), display: true)
        } else {
            let visibleFrame = screen.visibleFrame
            window.setFrameOrigin(NSPoint(
                x: visibleFrame.maxX - window.frame.width - 12,
                y: visibleFrame.maxY - window.frame.height - 12
            ))
        }
    }

    @objc private func wakeFromSleep(_ notification: Notification) {
        if Preferences.countdownDate <= Date() {
            stopKeepAwake()
        }
        guard window.isVisible else {
            updateMenuState()
            return
        }
        forceSync()
    }

    @objc private func close(_ sender: Any? = nil) {
        quit()
    }

    @objc private func quit(_ sender: Any? = nil) {
        NSApp.terminate(nil)
    }

    @objc private func forceSync(_ sender: Any? = nil) {
        syncState = "syncing"
        refreshDisplay()
        clock.sync { [weak self] status in
            guard let self else { return }
            self.syncState = status
            if status != "syncing" && status != "sync failed" {
                self.configureCountdownServices()
            }
            self.refreshDisplay()
        }
    }

    private func syncQuietly() {
        syncState = "syncing"
        clock.sync { [weak self] status in
            guard let self else { return }
            self.syncState = status
            if status != "syncing" && status != "sync failed" {
                self.configureCountdownServices()
            }
            self.refreshDisplay()
        }
    }

    private func refreshDisplay() {
        guard let date = clock.currentServerDate() else {
            view.setTime(Preferences.showHundredths ? "--:--:--.--" : "--:--:--")
            view.dateLabel.stringValue = "Asia/Taipei"
            view.setStatus(syncState, color: syncState == "sync failed" ? .systemRed : .systemYellow)
            updateStatusItem(serverDate: nil)
            return
        }

        view.titleLabel.stringValue = countdownTitle()
        if Preferences.displayMode == .countdown && Preferences.countdownActive {
            let remaining = Preferences.countdownDate.timeIntervalSince(date)
            if remaining <= 0 {
                view.setTime("TARGET REACHED")
                view.dateLabel.stringValue = "Target \(countdownDateFormatter.string(from: Preferences.countdownDate))"
                stopKeepAwake()
            } else {
                view.setTime(formatCountdownInterval(
                    remaining,
                    showHundredths: Preferences.showHundredths
                ))
                if Preferences.dualTime {
                    view.dateLabel.stringValue = "Now \(secondsFormatter.string(from: date))  •  \(countdownShortFormatter.string(from: Preferences.countdownDate))"
                } else {
                    view.dateLabel.stringValue = "Target \(countdownDateFormatter.string(from: Preferences.countdownDate))"
                }
            }
            view.dateLabel.toolTip = "Target \(countdownDateFormatter.string(from: Preferences.countdownDate)) Asia/Taipei"
        } else if Preferences.displayMode == .countdown {
            view.setTime("NO TARGET")
            view.dateLabel.stringValue = "Choose Set Countdown from the menu"
        } else {
            let formatter = Preferences.showHundredths ? hundredthsFormatter : secondsFormatter
            view.setTime(formatter.string(from: date))
            view.dateLabel.stringValue = dateFormatter.string(from: date)
            view.dateLabel.toolTip = "Estimated Tixcraft domain time in Asia/Taipei"
        }

        if syncState == "syncing" || syncState == "sync failed" {
            view.setStatus(syncState, color: syncState == "sync failed" ? .systemRed : .systemYellow)
        } else if let lastSync = clock.lastSync {
            let age = Int(Date().timeIntervalSince(lastSync))
            let staleAfter = max(Int(Preferences.syncInterval * 3), 60)
            let source = clock.source?.rawValue ?? "unknown source"
            if age > staleAfter {
                view.setStatus("stale \(age)s • \(source)", color: .systemOrange)
            } else {
                let ageText = age < 2 ? "synced" : "synced \(age)s ago"
                view.setStatus("\(ageText) • \(source)", color: .systemGreen)
            }
        }

        view.metricsLabel.stringValue = formatMetrics(clock.currentMetrics())
        updateStatusItem(serverDate: date)
    }

    private func formatMetrics(_ snap: MetricsSnapshot) -> String {
        func rounded(_ value: Double?, scale: Double = 1) -> String {
            value.map { String(format: "%.0f", $0 * scale) } ?? "--"
        }
        let rtt = rounded(snap.rttMedian, scale: 1000)
        let jit = snap.rttJitter.map { String(format: "±%.0f", $0 * 1000) } ?? ""
        let ttfb = rounded(snap.ttfb, scale: 1000)
        let vbe = rounded(snap.vbeMillis)
        return "RTT \(rtt)\(jit)  TTFB \(ttfb)  VBE \(vbe) ms"
    }

    func windowDidResize(_ notification: Notification) {
        view.applyScale(for: window.contentView?.bounds.width ?? window.frame.width)
        if let screen = window.screen {
            saveFrame(for: screen)
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard !isSnapping, let visibleFrame = window.screen?.visibleFrame else { return }
        let frame = window.frame
        let margin: CGFloat = 8
        let threshold: CGFloat = 16
        let left = visibleFrame.minX + margin
        let right = visibleFrame.maxX - frame.width - margin
        let bottom = visibleFrame.minY + margin
        let top = visibleFrame.maxY - frame.height - margin
        var origin = frame.origin

        if abs(frame.minX - left) <= threshold { origin.x = left }
        if abs(frame.minX - right) <= threshold { origin.x = right }
        if abs(frame.minY - bottom) <= threshold { origin.y = bottom }
        if abs(frame.minY - top) <= threshold { origin.y = top }

        if origin != frame.origin {
            isSnapping = true
            window.setFrameOrigin(origin)
            isSnapping = false
        }
        if let screen = window.screen {
            saveFrame(for: screen)
        }
    }
}

#if SELF_TEST
TixcraftClock.runSelfTests()
#else
private let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.run()
#endif
