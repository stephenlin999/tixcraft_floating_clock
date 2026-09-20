# Floating Clock: Next Useful Features

Date: 2026-09-20

## Scope and Current Baseline

Four comparable macOS tools are summarized from visited official product pages, a developer App Store listing, and a GitHub README. "Verified" means developer-documented, not independently tested. Recommendations combine those sources with inspection of the application at commit `a022ef0` and Apple's platform documentation. The implementation status below describes version 1.2.0 source and build verification; full cross-version runtime testing remains separate.

The supplied baseline already includes floating/always-on-top display, all Spaces, resizing, snapping, lock/click-through, opacity, compact mode, a global shortcut, one countdown target, and sync statistics. These are not new proposals. Hiding pauses display/sync timers; quitting terminates the app.

Inspection of [TixcraftFloatingTime.swift](TixcraftFloatingTime.swift) found that countdown clamps at zero (`formatCountdownInterval`), Clock/Countdown are mutually exclusive, and target entry requires Settings. Compact mode hides status/metrics (`setCompact`); the menu bar is icon-only (`configureStatusItem`); hiding stops display/sync timers (`stopClockActivity`). No alerts, sound, completion state, named targets, or quick presets were found.

## Verified Comparisons

| Tool | Verified useful behavior and primary source | Boundary to preserve |
| --- | --- | --- |
| Horo | Supports typed durations such as `60s` and `1.5hr`, clock-time targets such as `@12pm`, project tags such as `45m #writing`, and multiple timers in a Timer List. [Official product page, natural-language and multiple-timer sections](https://matthewpalmer.net/horo-free-timer-mac/). | Tags and quick entry are documented; reusable named target presets are not established by this page. |
| EzGestimer | Offers optional advance notifications a few minutes before expiry, extension of running timers, and selectable notification sounds. [Developer App Store listing, Key Features](https://apps.apple.com/us/app/ezgestimer/id6744532325?mt=12). | The listing does not establish arbitrary second-level thresholds, multiple warning stages, or delivery precision. |
| Madda Floating Clock | Remembers positions per monitor and restores them when an external display is connected/disconnected; with multiple monitors, it selects the largest screen. Also documents configurable Pomodoro durations and interval chimes every 5-60 minutes. [GitHub README, Features and Per-Monitor Position Memory](https://github.com/maddada/MaddaFloatingClock#per-monitor-position-memory). | Position restoration is not simultaneous clocks on every display. Periodic chimes are not countdown-threshold alerts. |
| CaffeineTimer | Provides 15/30/60/120-minute and custom keep-awake sessions, remaining time in the menu bar, an active-state icon, and automatic release of keep-awake at expiry. It separately allows the display to sleep. [Official product page, feature and workflow sections](https://vigodlabs.com/caffeine/). | Expiry releases the sleep restriction; it does not promise to force immediate sleep. This is an adjacent countdown utility, not a floating clock. |

## Implementation Status: Version 1.2.0

**Implemented: opt-in alerts and explicit completion.** The app schedules local alerts at 60 seconds, 10 seconds, and the target, skips thresholds already passed, and persists a `TARGET REACHED` display. These thresholds are our choices, not verified EzGestimer capabilities. Inspiration: [EzGestimer's advance alerts](https://apps.apple.com/us/app/ezgestimer/id6744532325?mt=12) and [CaffeineTimer's expiry notification](https://vigodlabs.com/caffeine/).

**Implemented: quick target entry and labels.** **Set Countdown…** accepts durations, Taipei clock times, or explicit dates, resolves the result before saving, and provides 5/10/30/60-minute presets. It keeps one active target and an optional label. [Horo's typed entry and tags](https://matthewpalmer.net/horo-free-timer-mac/) provide inspiration; reusable named saved presets remain deferred.

**Implemented: visible sync state.** Compact mode retains a color-coded recent/stale/failed indicator with tooltip and accessibility text. The detailed state identifies `X-Timer` versus HTTP `Date` and presents observation freshness rather than an accuracy guarantee. This extends the proposed [time-integrity requirements](SECURITY_GUIDELINES.md#5-time-integrity-and-targeted-logic-attacks).

**Implemented: dual time display.** Countdown mode can show the estimated domain time beside the target while keeping remaining time prominent.

**Implemented: menu bar remaining time.** While the clock is visible, the menu bar shows a short remaining-time or completion state. Hide stops display and sync timers and changes the title to `Paused`; already scheduled system alerts remain active. This is inspired by [CaffeineTimer's remaining-time display](https://vigodlabs.com/caffeine/).

**Implemented: temporary keep-awake and display memory.** Keep-awake is opt-in, visible in menus, has a separate display-awake choice, survives Hide, and releases on cancellation, completion, or normal Quit. The clock stores a frame for each display identity and restores the largest connected display after screen changes. Inspiration: [CaffeineTimer's bounded sessions](https://vigodlabs.com/caffeine/) and [Madda's per-monitor memory](https://github.com/maddada/MaddaFloatingClock#per-monitor-position-memory). Simultaneous mirrored clocks are outside scope.

## Implemented Behavior and Remaining Validation

The app uses one active target, an optional label, explicit duration or Taipei date/time inputs, and a resolved target preview. Named saved presets remain deferred until the single-target workflow has broader use.

Hiding pauses display and scheduled synchronization timers while an opted-in reminder uses system scheduling. Normal Quit or cancellation removes pending reminders. Forced termination cannot run the app's normal cancellation handler and may leave system-scheduled notifications pending. [Apple: scheduling and cancelling local notifications](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app)

Notification permission is requested when the user enables reminders, and its state is shown in Settings and the quick-target window. Successful scheduling does not guarantee an audible or precisely timed alert. [Apple: notification authorization](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications)

Visible countdown and reminders derive from the same recent accepted time estimate. An accepted synchronization or target edit replaces future pending deadlines; passed thresholds are recorded and skipped. Hidden reminders use the last schedule because periodic synchronization is paused. Sleep/wake, denied permission, forced termination, and multiple-display behavior still require runtime smoke testing on every supported macOS release; no reviewed source establishes subsecond alert reliability.

Keep-awake uses native ProcessInfo activity options and releases its activity on completion, cancellation, and normal Quit. Keeping the display awake is a separate option. It does not override lid closure or deliberate sleep. [Apple: activity options](https://developer.apple.com/documentation/foundation/processinfo/activityoptions), [Apple: ending an activity](https://developer.apple.com/documentation/foundation/processinfo/endactivity(_:))
