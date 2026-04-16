# HeartBit

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

### Download and Run on macOS
1. Go to the [GitHub Releases](https://github.com/ivans3m/HeartBit/releases) page and download the latest `HeartBit-<version>.zip`.
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

### Build from Source
1. Clone the repository.
2. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen).
3. Generate the Xcode project, open `HeartBit.xcodeproj`, then build and run on your Mac.

## Support & License
Designed for macOS 14.0+  
(c) 2026, Ivan Diuldia  
[ivan@diuldia.com](mailto:ivan@diuldia.com)
