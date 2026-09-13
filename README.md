# Tixcraft Floating Time

一個輕量的 macOS 拓元網域時間工具，提供浮動時鐘與狀態列控制。

A lightweight macOS utility that estimates Tixcraft domain time and provides a floating clock with native menu bar controls.

> Unofficial tool: this project is not affiliated with or endorsed by Tixcraft.

## Features

- Native macOS app with Dock, standard menus, Force Quit visibility, and a menu bar status item.
- Always-on-top floating window across Spaces.
- Draggable window with automatic position saving.
- Displays `HH:mm:ss.SS` with hundredths of a second, or whole seconds from Settings.
- Configurable synchronization interval: 15, 30, or 60 seconds.
- Uses `X-Timer` first and falls back to HTTP `Date`.
- Refuses off-host HTTPS redirects and malformed or implausible time headers.
- Hiding the clock pauses display and scheduled sync work; `X` and Quit fully terminate the app.
- App Sandbox and Hardened Runtime enabled in the local build.

## Requirements

- macOS 12 or later
- Xcode Command Line Tools with `swiftc` and `lipo`

## Quick Start

```zsh
git clone https://github.com/stephenlin999/tixcraft_floating_clock.git
cd tixcraft_floating_clock
./build_app.sh
open TixcraftTime.app
```

You can also run `./run.sh` directly.

The default build is a local ad-hoc signed Universal Binary for arm64 and x86_64. It is suitable for local use and testing. A public release should use a Developer ID Application identity:

```zsh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build_app.sh
```

After Developer ID signing, submit the resulting app to Apple Notarization before distributing it outside the Mac App Store.

## App Controls

The Dock icon and main menu provide About, Settings, Hide, Show Clock, and Quit. The menu bar icon provides Show/Hide Clock, Sync Now, Always on Top, Settings, and Quit.

Closing the floating clock with `X` quits the application. Choosing Hide keeps only the status item running, and choosing Quit stops all timers, cancels network requests, and exits the process.

## Technical Approach

The app is written in Swift/AppKit and sends a HEAD request to `https://tixcraft.com/activity`. It uses the RTT midpoint to compensate for network delay, then advances the synchronized time with macOS monotonic uptime instead of relying on per-second system-clock updates.

The response exposes both `X-Timer` and `Date` headers. `X-Timer` includes fractional seconds but usually represents CDN/edge time rather than the ticketing application's origin clock, so the displayed time is not guaranteed to exactly match the ticketing decision clock.

## Security and Scope

The app requires no account, credentials, or payment data. It does not automate ticket purchases or checkout. It only reads HTTP response headers from the fixed HTTPS target, validates the response host and time values, and cancels its timers and URLSession work during shutdown.

## Roadmap

- Developer ID signing and Apple Notarization in CI.
- macOS 12 and macOS 13 runtime smoke tests.
- Optional countdown and alert features without automating purchases or checkout.
- Additional time-source profiles after the single-source workflow is stable.

## Repository

[GitHub: stephenlin999/tixcraft_floating_clock](https://github.com/stephenlin999/tixcraft_floating_clock)

## License

MIT License. See [LICENSE](LICENSE).
