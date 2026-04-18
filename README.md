# HeartBit

*Minimal macOS menu bar task runner: schedule scripts and shell commands with cron-like control, catch-up policies, and local logging.*

HeartBit is a minimal, robust personal task runner for macOS that lives quietly in your menu bar. Built with native Swift and modern SwiftUI, it lets you schedule scripts, apps, and shell commands like `cron`, but with a native Mac interface.

### What it does
HeartBit runs your automation tasks on schedule in the background, with logging and safety controls designed for developer workflows. Typical use cases include recurring scripts, backups, local maintenance jobs, and app/command launch automation.

## Features
- **Precise Scheduling**: Run tasks down to the minute, hour, day, week, or month, with calendar-aware scheduling and an integrated Apple Calendar-style start time picker.
- **Sequential Pipeline**: Overlapping tasks queue safely in the background instead of competing for system resources. Watchdog timeouts automatically kill and report hanging scripts.
- **Missed Run Policies**: If your Mac is asleep during a scheduled run, HeartBit can catch up automatically or run once after wake.
- **Dynamic Dock Icon**: The app stays out of the way until needed, then shows its Dock icon when you open settings for easier window management.
- **Robust Local Logging**: Captures stdout and stderr from every run and stores logs in `~/Library/Logs/HeartBit/HeartBit.log` with configurable retention.

## Why isn't this on the Mac App Store?
HeartBit is designed to execute arbitrary shell scripts in the background, similar to a developer cron job. To support that, it intentionally runs without the Apple macOS App Sandbox (`ENABLE_APP_SANDBOX: "NO"`). Apple does not allow non-sandboxed apps on the Mac App Store.

Because of that, HeartBit is distributed directly through GitHub as a standalone macOS app.

## Installation

### Homebrew (recommended)
This repository is a [Homebrew tap](https://docs.brew.sh/Taps). Install HeartBit with:

```bash
brew tap ivans3m/heartbit
brew install --cask heartbit
```

If the short tap name does not resolve (unusual), use the full git URL:

```bash
brew tap ivans3m/heartbit https://github.com/ivans3m/homebrew-HeartBit.git
brew install --cask heartbit
```

**Uninstall**

```bash
brew uninstall --cask heartbit
```

To remove the tap as well (optional, only if you do not need updates from this tap):

```bash
brew untap ivans3m/heartbit
```

To remove the app plus associated logs and preferences defined in the cask (optional):

```bash
brew uninstall --zap --cask heartbit
```

### Download and run on macOS
1. Go to the [GitHub Releases](https://github.com/ivans3m/homebrew-HeartBit/releases) page and download the latest `HeartBit-v<version>.zip` (for example `HeartBit-v1.3.4.zip`).
2. Open the archive and drag `HeartBit.app` into your `/Applications` folder.
3. On first launch, macOS may warn that HeartBit is from an unidentified developer because it is distributed outside the App Store.
4. To open it the first time, go to `/Applications`, right-click `HeartBit.app`, choose **Open**, and confirm.
5. If macOS still blocks the app, run this in Terminal and try again:

```bash
xattr -dr com.apple.quarantine "/Applications/HeartBit.app"
```

6. After launch, look for the HeartBit icon in the **menu bar** (top-right). The app is menu-bar-first and may not show as a regular Dock app unless a settings window is open.

### Quick Start
1. Open HeartBit from the menu bar icon.
2. Create your first task (script/app/command).
3. Set its schedule and save.
4. Verify execution in logs:
   - In-app execution output
   - `~/Library/Logs/HeartBit/HeartBit.log`

### Troubleshooting
- **“App is damaged” / blocked by Gatekeeper**: run the quarantine command above and reopen.
- **No visible main window after launch**: check the macOS menu bar for the HeartBit icon.
- **Task did not run**: confirm schedule, Mac sleep state, and check logs for stdout/stderr details.

### Build from source
1. Clone the repository:

   ```bash
   git clone https://github.com/ivans3m/homebrew-HeartBit.git
   cd homebrew-HeartBit
   ```

2. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) (for example `brew install xcodegen`), or use the vendored binary under `./xcodegen` if present.
3. Generate the Xcode project, open `HeartBit.xcodeproj`, then build and run on your Mac.

### Release build (maintainers)
To produce a distributable zip matching release naming (`Release/HeartBit-v<version>.zip`), run:

```bash
./scripts/build_release.sh
```

The script reads the version from `project.yml`, builds the Release configuration, and writes `HeartBit-v<version>.zip` under `Release/`. It prints a SHA-256 checksum for updating [Casks/heartbit.rb](Casks/heartbit.rb) when you publish a new GitHub release.

## Support & License
Designed for macOS 14.0+  
(c) 2026, Ivan Diuldia  
[ivan@diuldia.com](mailto:ivan@diuldia.com)
