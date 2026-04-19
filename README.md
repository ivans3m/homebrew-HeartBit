# HeartBit

*Minimal macOS menu bar task runner: schedule scripts and shell commands with cron-like control, catch-up policies, and local logging.*

HeartBit is a minimal, robust personal task runner for macOS that lives quietly in your menu bar. Built with native Swift and modern SwiftUI, it lets you schedule scripts, apps, and shell commands like `cron`, but with a native Mac interface.

### What it does
HeartBit runs your automation tasks on schedule in the background, with logging and safety controls designed for developer workflows. Typical use cases include recurring scripts, backups, local maintenance jobs, and app/command launch automation.

## Features
- **Dual Engine Scheduling**: Run jobs in native HeartBit mode or Cron mode, with a per-job switch to choose the execution engine. In Cron mode, schedules are registered in your user `crontab`; missed-run catch-up applies only in HeartBit mode.
- **Crono & Crontab**: The **Crono** screen (sidebar, terminal icon) lists all jobs with a heart icon for HeartBit-scheduled jobs and a dotted-circle icon for Cron-scheduled jobs. Tap a job name to open its settings. Use **Crontab** at the bottom of Crono to view raw `crontab -l` output (Crontab is not a separate sidebar item).
- **Run every**: In **HeartBit** mode, choose **Run every:** from a picker (**Once**, common intervals, or **Custom**). The **5-field cron** field (`minute hour day month weekday`) appears only for **Custom**; preset intervals stay in the picker without exposing raw cron unless you need it. In **Cron** mode, you edit the cron line directly (what gets written to your user `crontab`).
- **Start & anchor time**: For **Once**, use **Start:** (calendar) and **Time** for the single run. For recurring schedules, only **Time (anchor)** is shown; it sets the clock anchor presets use (for example “every day at 09:30”). Changing **Start** or time updates the stored cron for **Cron** jobs and for **HeartBit + Custom** (simple fields are updated; steps like `*/5` and lists/ranges are left as-is). If you pick a clock time on **today** that is already in the past (common with a time-only control that keeps today’s date), HeartBit rolls the stored date forward by one day so the anchor means the **next** occurrence—typically **tomorrow** at that time—instead of firing immediately or staying in the past.
- **Execution controls**: In **Global Settings**, **PAUSED** stops all **HeartBit**-scheduled runs app-wide. Each job can also be turned off with **Enable Job** (or the sidebar toggle; disabled jobs show a pause icon). While paused or disabled, the background scheduler does **not** enqueue runs—editing a schedule or anchor time will not start a job. Manual **Run** / **Dry-Run** are disabled when execution is globally paused; they are still available for disabled jobs if you explicitly want a one-off run. **Cron**-engine jobs are driven by the system `crontab` when enabled, independent of HeartBit’s internal timer.
- **Precise Scheduling**: One-off runs use calendar + time; repeating jobs combine the time anchor with the chosen interval or custom cron.
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
1. Go to the [GitHub Releases](https://github.com/ivans3m/homebrew-HeartBit/releases) page and download the latest `HeartBit-v<version>.zip` (for example `HeartBit-v1.4.0.zip`).
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
2. Choose **Settings** to open the settings window (menu-bar-first apps may only show a Dock icon while Settings is open).
3. Under **Jobs**, create a task (script/app/command). Under **Crono**, see every job in one list; use **Crontab** there to inspect live `crontab -l` text.
4. Set engine (HeartBit or Cron), command, and schedule (picker + optional cron for Custom in HeartBit; cron line for Cron engine).
5. Security note: task commands run with your current macOS user permissions.
6. Verify execution in logs:
   - In-app execution output
   - `~/Library/Logs/HeartBit/HeartBit.log`

### Troubleshooting
- **“App is damaged” / blocked by Gatekeeper**: run the quarantine command above and reopen.
- **No visible main window after launch**: check the macOS menu bar for the HeartBit icon.
- **Task did not run**: confirm schedule, Mac sleep state, and check logs for stdout/stderr details.
- **“HeartBit wants to administer your computer” (or similar) when saving Cron jobs**: macOS shows this when the app updates your user `crontab`. The system decides whether to prompt; HeartBit cannot store an “always allow” answer inside the app. After you approve once, you should see fewer prompts; HeartBit also avoids rewriting `crontab` when nothing changed and batches rapid edits. If prompts persist, check **System Settings → Privacy & Security** for anything still pending for HeartBit, and ensure you are not running multiple copies of the app.

### Build from source
1. Clone the repository:

   ```bash
   git clone https://github.com/ivans3m/homebrew-HeartBit.git
   cd homebrew-HeartBit
   ```

2. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) (for example `brew install xcodegen`), or use the vendored binary under `./xcodegen` if present.
3. Generate the Xcode project, open `HeartBit.xcodeproj`, then build and run on your Mac.

### For developers (build scripts)
Canonical commands live under **`scripts/`**:

| Command | Purpose |
|--------|---------|
| `./scripts/heartbit-build.sh dev` | XcodeGen + **Debug** build, opens `HeartBit.app` for local testing. |
| `./scripts/heartbit-build.sh release` | XcodeGen + **Release** zip `Release/HeartBit-v<version>.zip` + prints SHA-256 (matches the Homebrew cask). |
| `./build.sh` | Optional **wrapper** at the repo root — same as `scripts/heartbit-build.sh` (e.g. `./build.sh release`). |

Do not use an old ad-hoc root script that calls `xcodebuild` on `HeartBit.xcodeproj` **without** running XcodeGen first, or that names zips `HeartBit-1.2.3.zip` (without the **`v`**): GitHub releases and [Casks/heartbit.rb](Casks/heartbit.rb) expect **`HeartBit-v<version>.zip`**.

CI runs **`./scripts/heartbit-build.sh release`** on every push/PR to `main` (see [.github/workflows/heartbit-ci.yml](.github/workflows/heartbit-ci.yml)).

### Release build (maintainers)
- **Test build (Debug, open app):** `./scripts/heartbit-build.sh dev`
- **Release zip for Homebrew** (`Release/HeartBit-v<version>.zip` + SHA-256 on stdout):

```bash
./scripts/heartbit-build.sh release
# or: ./scripts/build_release.sh
```

Version comes from `CFBundleShortVersionString` in [project.yml](project.yml).

### Publish a new version (maintainers)
Automated pipeline: bump version and build number in `project.yml`, build the zip, update [Casks/heartbit.rb](Casks/heartbit.rb), commit, tag `v<version>`, push, and create a **GitHub release** with notes generated from `git log` since the last tag.

**Requirements:** Xcode, XcodeGen, `gh` CLI (`gh auth login`), clean git status (unless `--allow-dirty`). Homebrew is optional but recommended for `brew audit --cask`.

```bash
./scripts/publish_release.sh --dry-run 1.4.0   # preview release notes; no changes
./scripts/publish_release.sh 1.4.0             # optional second arg: CFBundleVersion integer
./scripts/publish_release.sh --no-push --notes-out ./release-notes.md 1.4.0   # save notes if not using gh yet
```

For a detailed release checklist, see [.cursor/skills/heartbit-release/SKILL.md](.cursor/skills/heartbit-release/SKILL.md).

## Support & License
Designed for macOS 14.0+  
(c) 2026, Ivan Diuldia  
[ivan@diuldia.com](mailto:ivan@diuldia.com)
