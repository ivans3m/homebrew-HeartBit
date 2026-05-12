# AI / agent context

This repository is **HeartBit**, a native macOS menu bar app (Swift / SwiftUI), built with **XcodeGen** from [`project.yml`](project.yml).

- **Project rules:** [`.cursor/rules/`](.cursor/rules/) — `heartbit-core` (always); `release-homebrew` (`scripts/**`); `homebrew-cask-and-ci` (`Casks/**`); `project-yml` (`project.yml`). See [`.cursor/README.md`](.cursor/README.md).
- **Release workflow:** [`.cursor/skills/heartbit-release/SKILL.md`](.cursor/skills/heartbit-release/SKILL.md)
- **Human docs:** [README.md](README.md)
- **Auth-related job features** (Run in Terminal, login-shell toggle, per-job timeout, `needs-auth` status, `NSAppleEventsUsageDescription`): see the **Authentication & permissions** section in [README.md](README.md).

When changing versions or distribution artifacts, keep **`project.yml`**, **`Casks/heartbit.rb`**, and GitHub release assets aligned (see README maintainer sections).
