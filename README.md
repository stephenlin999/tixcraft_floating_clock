# Tixcraft Floating Time

一個輕量的 macOS 浮動時間視窗，使用 `https://tixcraft.com/activity` 的 HTTP 回應標頭估算拓元網域時間。

A lightweight macOS floating clock that estimates the time of the Tixcraft domain from HTTP response headers at `https://tixcraft.com/activity`.

> Unofficial tool: this project is not affiliated with or endorsed by Tixcraft.

## Features

- Always-on-top floating window across Spaces.
- Draggable window.
- Displays `HH:mm:ss.SS` with hundredths of a second.
- Resynchronizes every 15 seconds.
- Uses `X-Timer` first and falls back to HTTP `Date`.
- Stops timers, cancels requests, and exits cleanly on close.

## Requirements

- macOS 12 or later
- Xcode Command Line Tools with `swiftc`

## Quick Start

```zsh
git clone https://github.com/stephenlin999/tixcraft_floating_clock.git
cd tixcraft_floating_clock
./build_app.sh
open TixcraftTime.app
```

You can also run `./run.sh` directly.

## Technical Approach

The app is written in Swift/AppKit and sends a HEAD request to the target URL. It uses the RTT midpoint to compensate for network delay, then advances the synchronized time with macOS monotonic uptime instead of relying on per-second system-clock updates.

The `/activity` response exposes both `X-Timer` and `Date` headers, which are used as the current time anchor for the Tixcraft domain.

HTTP `Date` has only second-level precision. `X-Timer` includes fractional seconds but usually represents CDN/edge time rather than the ticketing application's origin clock, so the displayed time is not guaranteed to exactly match the ticketing decision clock.

## Proposed Roadmap

The goal is to evolve from a single-site clock into a verifiable, extensible, privacy-conscious edge-time toolkit.

- **Multi-source profiles**: support custom endpoints and time-source profiles for different ticketing platforms.
- **Synchronization confidence**: make offset, RTT, jitter, and estimated error understandable at a glance.
- **Sale countdown and alerts**: countdowns, sound cues, and configurable lead time without automating purchases or checkout.
- **Replayable network tests**: simulate latency, jitter, malformed headers, and connection failures.
- **Release-grade distribution**: Universal Binary builds, CI packaging, signing, and notarization.

## Security and Scope

The app requires no account, credentials, or payment data. It does not automate ticket purchases or checkout. It only reads HTTP response headers from the target and cancels its timers and URLSession work during shutdown.

## Repository

[GitHub: stephenlin999/tixcraft_floating_clock](https://github.com/stephenlin999/tixcraft_floating_clock)
