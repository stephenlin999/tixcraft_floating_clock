# App Icon Refresh Handoff

- **Branch:** `codex/app-icon-refresh` (tracks `origin/codex/app-icon-refresh`).
- **Updated:** 2026-09-24 12:41 CST (Asia/Taipei).
- **Work item:** Center the Tixcraft Time logo within a round macOS app icon, package standard icon sizes, and update the copies users see in Dock and Applications.
- **Status:** in progress.
- **Last commit:** `3553ad11bd581b67af16813b619a2e8542270030` (implementation commit at the time this handoff was written; the handoff is committed separately).
- **Pushed:** yes; the implementation branch has upstream tracking. This handoff is committed and pushed in the following commit, whose hash cannot be embedded in itself.

## Done (with evidence)

- Confirmed the Dock entry pointed to `/Applications/TixcraftTime.app`, which still contained version 1.1.0 build 2 and the old icon. The desktop project also had an older app copy.
- Added a deterministic AppKit renderer that measures the dark artwork pixels and centers the original ticket-and-clock design on a 1024 px canvas. The final artwork bounds were `612x368+206+328`, centered at `(512,512)`; the circular alpha bounds were `824x824+100+100`, also centered at `(512,512)`.
- Added `build_icon.sh` to generate all ten standard PNG slots and use macOS `iconutil` to make the ICNS. `zsh build_icon.sh` ran successfully outside the restricted execution sandbox. `iconutil -c iconset` decoded all ten slots; 16 px and 32 px images were visually checked without the earlier color corruption.
- Updated `build_app.sh` to package the icon under `TixcraftTime-Round.icns` and set `CFBundleIconFile` accordingly, so macOS does not reuse the old icon name's cache entry.
- Installed the resulting ICNS into the worktree app, the desktop project app, and `/Applications/TixcraftTime.app`; updated each bundle's icon key; renewed their ad-hoc Hardened Runtime signatures; verified each with `codesign --verify --deep --strict`; refreshed Launch Services and Dock. The three installed icon resources had the same SHA-256: `b6733749212cd651e248c84be6cb5e18e54b49e4b85910635044e18f24812120`.
- A Dock screenshot after the update showed the round icon. The screenshot and temporary rollback copies were under `/tmp` and no longer existed when this handoff was written; they are not durable evidence. On 2026-09-24, the installed app still reported `TixcraftTime-Round.icns` and version 1.1.0 build 2, while the worktree app reported version 1.2.0.
- Stopped or confirmed absent all build, rendering, screenshot, and Tixcraft processes started for this work. The worktree's five icon changes were committed and pushed on this branch.

## Not done

- The Launchpad / Applications-area icon was not conclusively inspected. A Launchpad screenshot command was interrupted, and the screenshot is no longer available. The Dock icon was inspected.
- `./build_app.sh` was not run after the `CFBundleIconFile` rename; the worktree app was patched and re-signed directly. A clean full build is still needed before release.
- The installed `/Applications/TixcraftTime.app` and desktop project app remain on version 1.1.0 build 2; this task replaced only their icon resources and metadata. The worktree app is version 1.2.0 build 3.
- No commit was made to `main`, and no notarized release was produced.

## Next step

After the supervisor moves the main repository, repair this linked worktree if Git cannot resolve its metadata. From the moved main repository, use `git worktree repair /Users/stephenlin/.codex/worktrees/34fa/tixcraft_time`, then verify `git -C /Users/stephenlin/.codex/worktrees/34fa/tixcraft_time status -sb`. Run a clean `./build_app.sh`, inspect the icon in Dock and Launchpad, and decide whether to distribute the rebuilt 1.2.0 app. Do not treat the icon-only update of the installed 1.1.0 app as a full application upgrade.

## How to verify

| Command | State and result |
| --- | --- |
| `zsh build_icon.sh` | **Ran, passed.** Native renderer and `iconutil` produced the icon. |
| `iconutil -c iconset assets/app-icon/TixcraftTime.icns -o /tmp/tixcraft-centered-final.iconset` | **Ran, passed.** All ten standard PNG slots were decoded; temporary output has since expired. |
| `magick assets/app-icon/source-minimal-ticket-clock-light-rounded.png -background white -alpha remove -colorspace gray -threshold 65% -negate -trim -format '%wx%h%O' info:` | **Ran, passed.** Artwork bounds: `612x368+206+328`. |
| `magick assets/app-icon/source-minimal-ticket-clock-light-rounded.png -alpha extract -threshold 50% -trim -format '%wx%h%O' info:` | **Ran, passed.** Circle bounds: `824x824+100+100`. |
| `codesign --verify --deep --strict /Applications/TixcraftTime.app` | **Ran, passed** after the icon installation. The installation script also checked the other two app copies. |
| `shasum -a 256 assets/app-icon/TixcraftTime.icns /Applications/TixcraftTime.app/Contents/Resources/TixcraftTime-Round.icns` | **Ran, matched.** Both hashes were `b6733749212cd651e248c84be6cb5e18e54b49e4b85910635044e18f24812120`. |
| `zsh -n build_icon.sh build_app.sh` | **Ran, passed.** |
| `git diff --check` | **Ran, passed** before the implementation commit. |
| `./build_app.sh` | **Not run** after the icon filename change. |
| Launchpad search and visual inspection | **Not completed**; the command was interrupted. |

## Files touched

- `build_app.sh`
- `build_icon.sh`
- `render_icon.swift`
- `assets/app-icon/TixcraftTime.icns`
- `assets/app-icon/source-minimal-ticket-clock-light-rounded.png`
- `docs/handoffs/codex-app-icon-refresh.md` (this handoff)

## Dependencies and impact

- Build tools: Swift/AppKit, `sips`, `iconutil`, `codesign`, and ImageMagick for the recorded measurement only. No third-party runtime dependency was added.
- The app copies at `/Applications/TixcraftTime.app`, `/Users/stephenlin/Desktop/tixcraft_time/TixcraftTime.app`, and the worktree's `TixcraftTime.app` were changed outside Git. Their signatures are local ad-hoc signatures, not Developer ID release signatures. Dock and Launch Services were refreshed during installation.
- This worktree's `.git` file resolves through `/Users/stephenlin/Desktop/tixcraft_time/.git/worktrees/tixcraft_time1`; its common Git directory is `/Users/stephenlin/Desktop/tixcraft_time/.git`. Relocating the main repository can break the linked worktree until Git's worktree references are repaired. No repository move was performed in this task.

## Absolute paths relied on

- Current worktree: `/Users/stephenlin/.codex/worktrees/34fa/tixcraft_time`
- Current main repository: `/Users/stephenlin/Desktop/tixcraft_time`
- Planned main repository destination (not present when checked): `/Users/stephenlin/Projects/tixcraft_time`
- Worktree Git metadata: `/Users/stephenlin/Desktop/tixcraft_time/.git/worktrees/tixcraft_time1`
- Shared Git metadata: `/Users/stephenlin/Desktop/tixcraft_time/.git`
- Installed app: `/Applications/TixcraftTime.app`
- Installed icon resource: `/Applications/TixcraftTime.app/Contents/Resources/TixcraftTime-Round.icns`
- Desktop project app: `/Users/stephenlin/Desktop/tixcraft_time/TixcraftTime.app`
- Desktop project icon resource: `/Users/stephenlin/Desktop/tixcraft_time/TixcraftTime.app/Contents/Resources/TixcraftTime-Round.icns`
- Worktree app: `/Users/stephenlin/.codex/worktrees/34fa/tixcraft_time/TixcraftTime.app`
- Worktree app icon resource: `/Users/stephenlin/.codex/worktrees/34fa/tixcraft_time/TixcraftTime.app/Contents/Resources/TixcraftTime-Round.icns`
- Original icon image: `/Users/stephenlin/.codex/worktrees/34fa/tixcraft_time/assets/app-icon/source-minimal-ticket-clock-light.png`
- Centered icon image: `/Users/stephenlin/.codex/worktrees/34fa/tixcraft_time/assets/app-icon/source-minimal-ticket-clock-light-rounded.png`
- Packaged icon: `/Users/stephenlin/.codex/worktrees/34fa/tixcraft_time/assets/app-icon/TixcraftTime.icns`
- Build scripts: `/Users/stephenlin/.codex/worktrees/34fa/tixcraft_time/build_icon.sh`, `/Users/stephenlin/.codex/worktrees/34fa/tixcraft_time/render_icon.swift`, `/Users/stephenlin/.codex/worktrees/34fa/tixcraft_time/build_app.sh`
- Handoff: `/Users/stephenlin/.codex/worktrees/34fa/tixcraft_time/docs/handoffs/codex-app-icon-refresh.md`

The earlier installer staging directory and screenshots under `/tmp` were ephemeral and do not exist now. The pushed Git branch and the committed handoff are the durable record.

## Risks and open questions

- Launchpad can cache an icon separately from Dock. Verify it after the repository move if the user still sees a square icon there.
- The ad-hoc re-signing of installed apps is suitable for local testing, not a notarized public release.
- Confirm that the supervisor's repository move preserves or repairs the linked worktree before attempting more Git operations in this checkout.
