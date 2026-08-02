import AppKit
import Foundation

private let tixcraftURL = URL(string: "https://tixcraft.com/activity")!
private let timeZone = TimeZone(identifier: "Asia/Taipei")!

private final class ClickThroughButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct FetchMetrics {
    var tcpConnect: TimeInterval?
    var tlsHandshake: TimeInterval?
    var ttfb: TimeInterval?
    var totalDuration: TimeInterval?
    var vbeMillis: Double?
}

private final class MetricsCapturingDelegate: NSObject, URLSessionTaskDelegate {
    private let onMetrics: (FetchMetrics) -> Void
    private var fired = false

    init(onMetrics: @escaping (FetchMetrics) -> Void) {
        self.onMetrics = onMetrics
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting taskMetrics: URLSessionTaskMetrics) {
        guard !fired else { return }
        fired = true
        var m = FetchMetrics()
        m.totalDuration = taskMetrics.taskInterval.duration
        if let tx = taskMetrics.transactionMetrics.last {
            if let cs = tx.connectStartDate, let ce = tx.connectEndDate {
                m.tcpConnect = ce.timeIntervalSince(cs)
            }
            if let ss = tx.secureConnectionStartDate, let se = tx.secureConnectionEndDate {
                m.tlsHandshake = se.timeIntervalSince(ss)
            }
            if let reqEnd = tx.requestEndDate, let respStart = tx.responseStartDate {
                m.ttfb = respStart.timeIntervalSince(reqEnd)
            }
        }
        onMetrics(m)
    }
}

private struct MetricsSnapshot {
    var rttMedian: TimeInterval?
    var rttJitter: TimeInterval?
    var ttfb: TimeInterval?
    var vbeMillis: Double?
    var sampleCount: Int = 0
}

private final class FloatingTimeView: NSView {
    let titleLabel = NSTextField(labelWithString: "TIXCRAFT")
    let timeLabel = NSTextField(labelWithString: "--:--:--.--")
    let dateLabel = NSTextField(labelWithString: "syncing...")
    let statusLabel = NSTextField(labelWithString: "connecting")
    let metricsLabel = NSTextField(labelWithString: "RTT --  TTFB --  VBE --")
    let syncButton = ClickThroughButton(title: "Sync", target: nil, action: nil)
    let closeButton = ClickThroughButton(title: "x", target: nil, action: nil)

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var dragStart: NSPoint?

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

        NSLayoutConstraint.activate([
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
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let dragStart else { return }
        let current = event.locationInWindow
        var origin = window.frame.origin
        origin.x += current.x - dragStart.x
        origin.y += current.y - dragStart.y
        window.setFrameOrigin(origin)
    }
}

private final class TixcraftClock {
    private struct ServerSample {
        let serverDate: Date
        let midpoint: TimeInterval
        let roundTrip: TimeInterval
        let metrics: FetchMetrics?
    }

    private(set) var baseServerDate: Date?
    private(set) var baseUptime: TimeInterval = 0
    private(set) var lastSync: Date?
    private(set) var lastStatus = "connecting"
    private var isSyncing = false
    private let shutdownLock = NSLock()
    private var shutdownRequested = false

    private var rttSamples: [TimeInterval] = []
    private var lastTTFB: TimeInterval?
    private var lastVBE: Double?
    private let maxSamples = 10

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
        guard let baseServerDate else { return nil }
        let elapsed = ProcessInfo.processInfo.systemUptime - baseUptime
        return baseServerDate.addingTimeInterval(elapsed)
    }

    func currentMetrics() -> MetricsSnapshot {
        var snap = MetricsSnapshot()
        snap.sampleCount = rttSamples.count
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

    func sync(completion: @escaping (Bool, String) -> Void) {
        guard !isShutDown else { return }
        guard !isSyncing else {
            completion(false, "syncing")
            return
        }
        isSyncing = true
        collectBoundarySample(previous: nil, deadline: ProcessInfo.processInfo.systemUptime + 2.2, completion: completion)
    }

    private func recordMetrics(_ sample: ServerSample) {
        rttSamples.append(sample.roundTrip)
        if rttSamples.count > maxSamples {
            rttSamples.removeFirst(rttSamples.count - maxSamples)
        }
        if let ttfb = sample.metrics?.ttfb {
            lastTTFB = ttfb
        }
        if let vbe = sample.metrics?.vbeMillis {
            lastVBE = vbe
        }
    }

    private func finishSync(
        serverDate: Date,
        uptime: TimeInterval,
        status: String,
        ok: Bool,
        completion: @escaping (Bool, String) -> Void
    ) {
        guard !isShutDown else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isShutDown else { return }
            if ok {
                self.baseServerDate = serverDate
                self.baseUptime = uptime
                self.lastSync = Date()
            }
            self.lastStatus = status
            self.isSyncing = false
            completion(ok, status)
        }
    }

    private func collectBoundarySample(
        previous: ServerSample?,
        deadline: TimeInterval,
        completion: @escaping (Bool, String) -> Void
    ) {
        guard !isShutDown else { return }
        fetchSample { [weak self] sample in
            guard let self, !self.isShutDown else { return }
            guard let sample else {
                self.finishSync(
                    serverDate: self.baseServerDate ?? Date(),
                    uptime: self.baseUptime,
                    status: "sync failed",
                    ok: false,
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
                    serverDate: sample.serverDate,
                    uptime: boundaryUptime,
                    status: "edge sync",
                    ok: true,
                    completion: completion
                )
                return
            }

            if ProcessInfo.processInfo.systemUptime >= deadline {
                self.finishSync(
                    serverDate: sample.serverDate,
                    uptime: sample.midpoint,
                    status: "sec sync",
                    ok: true,
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
        request.setValue("Mozilla/5.0 TixcraftFloatingTime/1.0", forHTTPHeaderField: "User-Agent")

        let started = ProcessInfo.processInfo.systemUptime
        let lock = NSLock()
        var capturedMetrics: FetchMetrics?
        var ended: TimeInterval = started
        var capturedResponse: HTTPURLResponse?
        var hadError = false

        let group = DispatchGroup()
        group.enter()
        group.enter()

        let delegate = MetricsCapturingDelegate { metrics in
            lock.lock()
            capturedMetrics = metrics
            lock.unlock()
            group.leave()
        }

        let task = session.dataTask(with: request) { _, response, error in
            lock.lock()
            ended = ProcessInfo.processInfo.systemUptime
            capturedResponse = response as? HTTPURLResponse
            hadError = (error != nil)
            lock.unlock()
            group.leave()
        }
        task.delegate = delegate
        task.resume()

        group.notify(queue: DispatchQueue.global(qos: .utility)) { [weak self] in
            guard let self, !self.isShutDown else { return }
            guard !hadError, let http = capturedResponse else {
                completion(nil)
                return
            }
            guard let parsed = Self.parseHighPrecisionTime(from: http) else {
                completion(nil)
                return
            }
            var metrics = capturedMetrics
            if let xTimer = http.value(forHTTPHeaderField: "X-Timer"),
               let vbe = Self.parseXTimerVBE(xTimer) {
                if metrics == nil { metrics = FetchMetrics() }
                metrics?.vbeMillis = vbe
            }
            let midpoint = started + max(0, ended - started) / 2
            completion(ServerSample(
                serverDate: parsed,
                midpoint: midpoint,
                roundTrip: ended - started,
                metrics: metrics
            ))
        }
    }

    private static func parseHTTPDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss zzz"
        return formatter.date(from: string)
    }

    private static func parseHighPrecisionTime(from response: HTTPURLResponse) -> Date? {
        if let xTimer = response.value(forHTTPHeaderField: "X-Timer"),
           let startEpoch = parseXTimerStart(xTimer) {
            return Date(timeIntervalSince1970: startEpoch)
        }

        if let dateValue = response.value(forHTTPHeaderField: "Date") {
            return parseHTTPDate(dateValue)
        }

        return nil
    }

    private static func parseXTimerStart(_ string: String) -> TimeInterval? {
        for part in string.split(separator: ",") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("S") && !trimmed.hasPrefix("SC") {
                return TimeInterval(trimmed.dropFirst())
            }
        }
        return nil
    }

    private static func parseXTimerVBE(_ string: String) -> Double? {
        for part in string.split(separator: ",") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("VBE") {
                return Double(trimmed.dropFirst(3))
            }
        }
        return nil
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let view = FloatingTimeView(frame: NSRect(x: 0, y: 0, width: 286, height: 132))
    private let clock = TixcraftClock()
    private var window: NSWindow!
    private var displayTimer: Timer?
    private var syncTimer: Timer?
    private var isShuttingDown = false

    private lazy var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm:ss.SS"
        return formatter
    }()

    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        shutdown()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let size = view.frame.size
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(x: screenFrame.maxX - size.width - 28, y: screenFrame.maxY - size.height - 28)

        window = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.makeKeyAndOrderFront(nil)

        view.closeButton.target = self
        view.closeButton.action = #selector(close)
        view.syncButton.target = self
        view.syncButton.action = #selector(forceSync)

        forceSync()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
            self?.refreshDisplay()
        }
        syncTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.syncQuietly()
        }
    }

    @objc private func close() {
        shutdown()
        NSApplication.shared.terminate(nil)
    }

    private func shutdown() {
        guard !isShuttingDown else { return }
        isShuttingDown = true

        displayTimer?.invalidate()
        displayTimer = nil
        syncTimer?.invalidate()
        syncTimer = nil
        view.closeButton.target = nil
        view.closeButton.action = nil
        view.syncButton.target = nil
        view.syncButton.action = nil
        clock.shutdown()
        window?.orderOut(nil)
    }

    @objc private func forceSync() {
        view.statusLabel.stringValue = "syncing"
        clock.sync { [weak self] ok, status in
            self?.view.statusLabel.stringValue = ok ? status : status
            self?.refreshDisplay()
        }
    }

    private func syncQuietly() {
        clock.sync { [weak self] _, status in
            self?.view.statusLabel.stringValue = status
        }
    }

    private func refreshDisplay() {
        guard let date = clock.currentServerDate() else {
            view.timeLabel.stringValue = "--:--:--.--"
            view.dateLabel.stringValue = "Asia/Taipei"
            return
        }

        view.timeLabel.stringValue = timeFormatter.string(from: date)
        view.dateLabel.stringValue = dateFormatter.string(from: date)

        if let lastSync = clock.lastSync {
            let age = Int(Date().timeIntervalSince(lastSync))
            view.statusLabel.stringValue = age < 2 ? "synced" : "synced \(age)s ago"
        }

        view.metricsLabel.stringValue = formatMetrics(clock.currentMetrics())
    }

    private func formatMetrics(_ snap: MetricsSnapshot) -> String {
        func ms(_ s: TimeInterval?) -> String {
            guard let s else { return "--" }
            return String(format: "%.0f", s * 1000)
        }
        func msInt(_ d: Double?) -> String {
            guard let d else { return "--" }
            return String(format: "%.0f", d)
        }
        let rtt = ms(snap.rttMedian)
        let jit = snap.rttJitter.map { String(format: "±%.0f", $0 * 1000) } ?? ""
        let ttfb = ms(snap.ttfb)
        let vbe = msInt(snap.vbeMillis)
        return "RTT \(rtt)\(jit)  TTFB \(ttfb)  VBE \(vbe) ms"
    }
}

private let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.run()
