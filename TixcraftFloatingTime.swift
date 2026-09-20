import AppKit
import Carbon.HIToolbox
import Foundation

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
            countdownDateKey: Date().addingTimeInterval(3600).timeIntervalSince1970
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
}

private final class SettingsWindowController: NSObject {
    let window: NSWindow
    var onChange: (() -> Void)?

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
    private let opacitySlider = NSSlider(value: 88, minValue: 35, maxValue: 100, target: nil, action: nil)
    private let opacityValueLabel = NSTextField(labelWithString: "88%")

    override init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 390),
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
        opacityValueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)

        [
            alwaysOnTopButton,
            showHundredthsButton,
            compactModeButton,
            lockPositionButton,
            clickThroughButton,
            intervalPopup,
            modeControl,
            countdownPicker,
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
            countdownRow
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
        opacitySlider.doubleValue = Double(Preferences.backgroundOpacity * 100)
        opacityValueLabel.stringValue = "\(Int(opacitySlider.doubleValue.rounded()))%"
    }

    @objc private func settingChanged() {
        Preferences.alwaysOnTop = alwaysOnTopButton.state == .on
        Preferences.showHundredths = showHundredthsButton.state == .on
        Preferences.compactMode = compactModeButton.state == .on
        Preferences.lockPosition = lockPositionButton.state == .on
        Preferences.clickThrough = clickThroughButton.state == .on
        Preferences.backgroundOpacity = CGFloat(opacitySlider.doubleValue / 100)
        Preferences.displayMode = modeControl.selectedSegment == 1 ? .countdown : .clock
        Preferences.countdownDate = countdownPicker.dateValue
        opacityValueLabel.stringValue = "\(Int(opacitySlider.doubleValue.rounded()))%"
        if let seconds = intervalPopup.selectedItem?.tag {
            Preferences.syncInterval = TimeInterval(seconds)
        }
        onChange?()
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
            syncButton.widthAnchor.constraint(equalToConstant: 42)
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
        [titleLabel, dateLabel, statusLabel, metricsLabel].forEach { $0.isHidden = compact }
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
        timeLabel.font = .monospacedDigitSystemFont(
            ofSize: (isCompact ? 30 : 32) * scale,
            weight: .semibold
        )
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
    private struct ServerSample {
        let serverDate: Date
        let midpoint: TimeInterval
        let roundTrip: TimeInterval
        let ttfb: TimeInterval?
        let vbeMillis: Double?
    }

    private var anchor: (date: Date, uptime: TimeInterval)?
    private(set) var lastSync: Date?
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
        status: String,
        completion: @escaping (String) -> Void
    ) {
        guard !isShutDown else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isShutDown else { return }
            if let anchor {
                self.anchor = anchor
                self.lastSync = Date()
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
                    status: "edge sync",
                    completion: completion
                )
                return
            }

            if ProcessInfo.processInfo.systemUptime >= deadline {
                self.finishSync(
                    anchor: (sample.serverDate, sample.midpoint),
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
                serverDate: parsed,
                midpoint: midpoint,
                roundTrip: ended - started,
                ttfb: capturedTTFB,
                vbeMillis: vbe
            ))
        }
    }

    private static func parseHighPrecisionTime(from response: HTTPURLResponse) -> Date? {
        if let xTimer = response.value(forHTTPHeaderField: "X-Timer"),
           let startEpoch = parseXTimerValue(xTimer, prefix: "S"),
           (946_684_800...4_102_444_800).contains(startEpoch) {
            return Date(timeIntervalSince1970: startEpoch)
        }

        if let dateValue = response.value(forHTTPHeaderField: "Date"),
           let date = httpDateFormatter.date(from: dateValue),
           (946_684_800...4_102_444_800).contains(date.timeIntervalSince1970) {
            return date
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
        precondition(isTrustedTixcraftURL(tixcraftURL))
        precondition(!isTrustedTixcraftURL(URL(string: "https://example.com/activity")))
        precondition(!isTrustedTixcraftURL(URL(string: "http://tixcraft.com/activity")))

        let validDate = Date(timeIntervalSince1970: 1_700_000_000)
        let dateHeader = httpDateFormatter.string(from: validDate)
        let validResponse = HTTPURLResponse(
            url: tixcraftURL,
            statusCode: 403,
            httpVersion: nil,
            headerFields: ["X-Timer": "S1700000000.25,VE12.5"]
        )!
        precondition(parseHighPrecisionTime(from: validResponse) != nil)

        let fallbackResponse = HTTPURLResponse(
            url: tixcraftURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["X-Timer": "S999", "Date": dateHeader]
        )!
        precondition(parseHighPrecisionTime(from: fallbackResponse) != nil)
        print("Self-tests passed")
    }
#endif
}

private final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let view = FloatingTimeView(frame: NSRect(x: 0, y: 0, width: 286, height: 132))
    private let clock = TixcraftClock()
    private var window: NSWindow!
    private var displayTimer: Timer?
    private var syncTimer: Timer?
    private var statusItem: NSStatusItem?
    private var globalHotKey: GlobalHotKey?
    private var settingsWindowController: SettingsWindowController?
    private var clockVisibilityItems: [NSMenuItem] = []
    private var alwaysOnTopItems: [NSMenuItem] = []
    private var compactModeItems: [NSMenuItem] = []
    private var lockPositionItems: [NSMenuItem] = []
    private var clickThroughItems: [NSMenuItem] = []
    private var displayModeItems: [NSMenuItem] = []
    private var appliedCompactMode: Bool?
    private var isSnapping = false
    private var syncState = "connecting"

    private let hundredthsFormatter = makeFormatter("HH:mm:ss.SS", timeZone: taipeiTimeZone)
    private let secondsFormatter = makeFormatter("HH:mm:ss", timeZone: taipeiTimeZone)
    private let dateFormatter = makeFormatter("yyyy/MM/dd", timeZone: taipeiTimeZone)
    private let countdownDateFormatter = makeFormatter("yyyy/MM/dd HH:mm:ss", timeZone: taipeiTimeZone)

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        stopClockActivity()
        clock.shutdown()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()
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
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(x: screenFrame.maxX - size.width - 28, y: screenFrame.maxY - size.height - 28)
        let frameName = "TixcraftFloatingClockWindow"

        window = FloatingWindow(
            contentRect: NSRect(origin: origin, size: size),
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
        if !window.setFrameUsingName(frameName) {
            window.setFrameOrigin(origin)
        }

        view.closeButton.target = self
        view.closeButton.action = #selector(close)
        view.syncButton.target = self
        view.syncButton.action = #selector(forceSync)
        view.menu = makeClockContextMenu()
        view.setAccessibilityLabel("Tixcraft floating clock")
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "TixcraftTimeStatusItem"
        item.isVisible = true
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "clock", accessibilityDescription: "Tixcraft Time")
            button.image?.isTemplate = true
            button.toolTip = "Tixcraft Time"
            button.setAccessibilityLabel("Tixcraft Time")
        }

        let menu = NSMenu(title: "Tixcraft Time")
        menu.addItem(makeVisibilityMenuItem())
        menu.addItem(menuItem("Sync Now", action: #selector(forceSync)))
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
        displayModeItems.forEach {
            $0.title = Preferences.displayMode == .clock ? "Show Countdown" : "Show Clock"
        }
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

    private func applyPreferences() {
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
        view.titleLabel.stringValue = Preferences.displayMode == .clock ? "TIXCRAFT" : "COUNTDOWN"
        settingsWindowController?.reload()
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
            controller.onChange = { [weak self] in
                self?.applyPreferences()
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

    @objc private func toggleDisplayMode(_ sender: Any? = nil) {
        Preferences.displayMode = Preferences.displayMode == .clock ? .countdown : .clock
        applyPreferences()
    }

    @objc private func moveToCurrentScreen(_ sender: Any? = nil) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        let origin = NSPoint(
            x: visibleFrame.maxX - window.frame.width - 12,
            y: visibleFrame.maxY - window.frame.height - 12
        )
        window.setFrameOrigin(origin)
        showClock()
    }

    @objc private func wakeFromSleep(_ notification: Notification) {
        guard window.isVisible else { return }
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
            self?.syncState = status
            self?.refreshDisplay()
        }
    }

    private func syncQuietly() {
        syncState = "syncing"
        clock.sync { [weak self] status in
            self?.syncState = status
            self?.refreshDisplay()
        }
    }

    private func refreshDisplay() {
        guard let date = clock.currentServerDate() else {
            view.timeLabel.stringValue = Preferences.showHundredths ? "--:--:--.--" : "--:--:--"
            view.dateLabel.stringValue = "Asia/Taipei"
            view.statusLabel.stringValue = syncState
            return
        }

        if Preferences.displayMode == .countdown {
            view.timeLabel.stringValue = formatCountdownInterval(
                Preferences.countdownDate.timeIntervalSince(date),
                showHundredths: Preferences.showHundredths
            )
            view.dateLabel.stringValue = "Target \(countdownDateFormatter.string(from: Preferences.countdownDate))"
        } else {
            let formatter = Preferences.showHundredths ? hundredthsFormatter : secondsFormatter
            view.timeLabel.stringValue = formatter.string(from: date)
            view.dateLabel.stringValue = dateFormatter.string(from: date)
        }

        if syncState == "syncing" || syncState == "sync failed" {
            view.statusLabel.stringValue = syncState
        } else if let lastSync = clock.lastSync {
            let age = Int(Date().timeIntervalSince(lastSync))
            let staleAfter = max(Int(Preferences.syncInterval * 3), 60)
            view.statusLabel.stringValue = age > staleAfter
                ? "stale \(age)s"
                : (age < 2 ? "synced" : "synced \(age)s ago")
        }

        view.metricsLabel.stringValue = formatMetrics(clock.currentMetrics())
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

        guard origin != frame.origin else { return }
        isSnapping = true
        window.setFrameOrigin(origin)
        isSnapping = false
    }
}

private let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate

#if SELF_TEST
TixcraftClock.runSelfTests()
#else
app.run()
#endif
