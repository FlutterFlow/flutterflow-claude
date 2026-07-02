# Changelog

All notable changes to the FlutterFlow plugin for Claude Code.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[SemVer](https://semver.org/). The version in
`plugins/flutterflow/.claude-plugin/plugin.json` must have a matching entry here —
CI enforces it, and the release notes for each tag are taken from that entry.

Note: marketplace installs track this repo's default branch, not the tags — run
`/plugin marketplace update flutterflow` to pull the latest. Tags mark which
commit a version number refers to.

## [Unreleased]

### Changed
- README install docs restructured: installing from GitHub
  (`/plugin marketplace add FlutterFlow/flutterflow-claude`) is the primary path;
  local-clone install is documented as the development/testing path, with the
  repo-root requirement for `marketplace add ./` spelled out and a troubleshooting
  note quoting the real CLI errors.

## [0.1.4] — 2026-07-02

### Added
- **Clipboard key hand-off** (`scripts/store-key-from-clipboard.sh`): the user
  copies their API key from <https://app.flutterflow.io/account> and tells Claude
  "I copied my FlutterFlow API key" — the bundled script reads the clipboard once,
  validates it against the UUID key format, writes
  `~/.config/flutterflow/claude-env.sh` (0600), and clears the clipboard. The key
  never enters the chat, tool output, argv, or shell variables (redirection-only;
  xtrace defeated; SSH/headless sessions refused with a fallback).
- Security-property test suite for the script (leak-freedom, rejection paths,
  symlink refusal, hook-marker non-collision), wired into CI.

### Changed
- SessionStart no-key notice now leads with the clipboard flow; the broken
  `/plugin configure` dialog is no longer suggested anywhere user-facing
  (the hook still bridges a configured token automatically).
- Build skill: key-setup paths reordered (clipboard → own-terminal one-liner →
  `flutterflow ai init` prompt) with hard no-leak rules — never bare clipboard
  reads, never cat credential files, fixed retry wording, compromised-key protocol.
- README/skill now reference the live upstream issue
  [anthropics/claude-code#73530](https://github.com/anthropics/claude-code/issues/73530)
  (configure dialog rejects input) instead of the mis-triaged, locked #51538.

## [0.1.3] — 2026-07-02

### Fixed
- **Hook no longer deletes hand-written key files.** Files written by the
  SessionStart hook are stamped with a `# managed-by: flutterflow-claude plugin`
  marker, and the hook's reconcile-delete only removes marker-stamped files. Users
  who create `~/.config/flutterflow/claude-env.sh` themselves (the documented
  fallback while the `/plugin configure` dialog is broken upstream) are no longer
  silently logged out at the next session start.
- Project URLs in skill guidance now include the `https://` scheme so they render
  as clickable links in chat.
- README: clearing the CLI credential cache requires `flutterflow ai logout --all`
  (bare `logout` only lists saved keys).

### Added
- Throttled (12h) session-start notice when no API key is configured, linking to
  <https://app.flutterflow.io/account>.
- Suppression of the no-key notice when a hand-written key file provides the key.

## [0.1.2] — 2026-07-01

First tagged release.

### Added
- CI: manifest validation, shell syntax checks, security-property tests for the
  SessionStart hook; auto-tag & GitHub release on version bump.
- Security-property test suite for the hook (0600/0700 perms, `%q` token quoting,
  symlink refusal, cleanup on token clear, HOME-unset safety).

### Changed
- Hardened token lifecycle from security review: tight perms from first write
  (umask 077), symlinked config dir/file refusal, pinned CLI version for the
  auto-install, throttled install attempts and notices.
- README rewritten for public / plugin-directory distribution.

## [0.1.1] — 2026-06-29

### Added
- Initial plugin: marketplace manifest, SessionStart hook that auto-installs the
  pinned `flutterflow_cli` (Dart-aware, fail-soft) and bridges the plugin's
  configured API token to `FF_API_KEY` for the CLI, and the `build` skill — a
  guided orient → validate → apply workflow over `flutterflow ai`.

[Unreleased]: https://github.com/FlutterFlow/flutterflow-claude/compare/v0.1.4...HEAD
[0.1.4]: https://github.com/FlutterFlow/flutterflow-claude/releases/tag/v0.1.4
[0.1.3]: https://github.com/FlutterFlow/flutterflow-claude/releases/tag/v0.1.3
[0.1.2]: https://github.com/FlutterFlow/flutterflow-claude/releases/tag/v0.1.2
[0.1.1]: https://github.com/FlutterFlow/flutterflow-claude/compare/dac575b...3980e4b
