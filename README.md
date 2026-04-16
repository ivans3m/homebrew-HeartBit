# HeartBit

HeartBit is a minimal, robust personal task runner for macOS that lives quietly in your menu bar. Built with native Swift and modern SwiftUI, it allows you to schedule scripts, apps, and shell commands just like `cron`, but with an elegant native Mac interface.

## Features
- **Precise Scheduling**: Run tasks down to the minute, hour, day, week, or month, precisely factoring in calendar variations. It features an integrated Apple Calendar-style UI for start times.
- **Sequential Pipeline**: Overlapping tasks safely queue sequentially in the background, rather than fighting for concurrent system resources. Watchdog timeouts (10m limit) automatically kill and report hanging scripts gracefully.
- **Missed Run Policies**: If your Mac goes to sleep and misses triggers, HeartBit can automatically *Catch Up* (running natively N times) or *Run Once* upon system wake to keep you flawlessly on schedule.
- **Dynamic Dock Icon**: Operates fully invisibly until you request it. Opening settings dynamically renders its app icon directly in your macOS Dock for easy window handling.
- **Robust Local Logging**: Captures stdout/stderr from every execution natively and pipes it globally into standard macOS file formats (`~/Library/Logs/HeartBit/HeartBit.log`) with integrated automatic retention loops (7, 30, or 90-day automated purges).

## Why isn't this on the Mac App Store?
HeartBit is specifically engineered to execute arbitrary shell scripts (ZSH, Python, etc.) seamlessly in the background just like a traditional developer cron-job. To achieve global execution mapping across your machine, the app intentionally opts out of the Apple macOS App Sandbox (`ENABLE_APP_SANDBOX: "NO"`). Apple strictly prohibits non-sandboxed applications on the Mac App Store. 

Consequently, HeartBit is distributed identically as an indie, unsandboxed standalone `.app` directly through GitHub.

## Installation

### Method A: Download the Pre-Compiled App (Recommended)
1. Go to the [Releases](#) page and download the latest `HeartBit.zip`.
2. Extract the archive and drag `HeartBit.app` to your `/Applications` folder.
3. Because the app is independently distributed outside the App Store and unsigned, macOS Gatekeeper may flag it as an "Unidentified Developer".
4. **To open it:** Navigate to your Applications folder, **Right-Click** the app, and select **Open**. You will only need to do this once.
   *(Alternatively, run `xattr -cr /Applications/HeartBit.app` in your Terminal to strip the quarantine flag).*

### Method B: Build from Source
1. Clone the repository natively.
2. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
3. Run `xcodegen` at the directory root to orchestrate the internal dependencies into standard Xcode format.
4. Open `HeartBit.xcodeproj` natively in Xcode.
5. Hit `Cmd+R` to compile and run.

## Support & License
Designed for macOS 14.0+  
(c) 2026, Ivan Diuldia  
[ivan@diuldia.com](mailto:ivan@diuldia.com)
