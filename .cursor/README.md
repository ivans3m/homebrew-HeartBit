# Cursor configuration (HeartBit)

## Rules (`.cursor/rules/`)

| File | Scope |
|------|--------|
| `heartbit-core.mdc` | Always — Swift app, XcodeGen, minimal edits |
| `release-homebrew.mdc` | When editing `scripts/**` |
| `homebrew-cask-and-ci.mdc` | When editing `Casks/**` |
| `project-yml.mdc` | When editing `project.yml` |

Rules use `.mdc` with YAML frontmatter (`description`, `alwaysApply`, `globs`).

## Skills (`.cursor/skills/`)

| Skill | Use when |
|-------|----------|
| `heartbit-release/` | Cutting a release: version bump, cask, tag, GitHub release |

## Tasks / todos

Work tracking is **not** stored in a single repo file by default. Use **GitHub Issues**, the **Cursor chat todo list**, or add a project-specific file (e.g. `docs/ROADMAP.md`) if you want a visible checklist in git.
