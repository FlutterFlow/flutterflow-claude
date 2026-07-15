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

## [0.1.6] — 2026-07-15

### Changed
- Build skill: project selection can use `flutterflow ai projects --json`
  (CLI > 0.0.38) to list the account's projects and present a picker via
  AskUserQuestion — top few most-recent projects plus free-text fuzzy match —
  falling back to asking for the project URL on CLIs without the command.

## [0.1.5] — 2026-07-14

Catches the plugin up with `flutterflow_cli` 0.0.38 and the current
`flutterflow ai` SDK surface (per-workspace MCP auto-registration, branch/merge
workflow, onboarding wizard).

### Changed
- **Pinned CLI bumped to `flutterflow_cli` 0.0.38** (from 0.0.37) — brings the
  interactive onboarding wizard (bare `flutterflow ai` in a terminal) and an
  `init` fast-fail when the target path already exists. The pin only affects
  fresh installs: the hook installs when `flutterflow` is missing, it does not
  upgrade an existing install.
- **README "Optional: native MCP" section replaced** with "Native MCP —
  registered automatically per workspace": `flutterflow ai init` (and
  `refresh-workspace`) now auto-register the FlutterFlow AI MCP server with
  detected agents — for Claude Code, a project-scoped `.mcp.json` at the
  workspace root — launching the workspace's vendored server directly with
  `dart run` and reading the key from the workspace `.flutterflow/.env`.
  Documents the MCP-only live FlutterFlow Desktop bridge, and notes the CLI
  itself supports Windows end-to-end (only the SessionStart hook needs `bash`).
- **Build skill refreshed against the 0.0.38 CLI/SDK:**
  - `init`: `--project` documented as optional — omitting it scaffolds an
    unbound workspace whose project is created on first `run`; documents the
    managed in-workspace guidance files (`CLAUDE.md`, `AGENTS.md`,
    `references/`, `patterns/`), the MCP auto-registration, and `--yes`.
  - New "Branches & merges" section covering the `branch` sub-commands
    (list/current/status/create/checkout/close/restore) and the three-way
    `merge` workflow (start/status/explain/auto/resolve/verify/commit/abort).
  - Orient: added `upgrade --check` (agent-parseable, last line
    `newer_available: true|false`); other-surfaces list gains `test`,
    `test-pilot`, `issue`, `mcp`.
  - Fixed the outside-workspace gotcha: commands fail with exit 1 and "No
    FlutterFlow AI workspace found from …" (not "exit 64 /
    No .flutterflow/config.yaml"), and the workspace root is found from any
    subdirectory, not just its top level.
  - Credential-cache gotcha refined: keys supplied via `FF_API_KEY` (this
    plugin's path) are never persisted to `~/.flutterflow/credentials.json`;
    the cache exists only after an interactive or `--api-key` init.
  - Key-setup fallback for SSH-less users now mentions the wizard (bare
    `flutterflow ai` in their own terminal).
- README install docs restructured: installing from GitHub
  (`/plugin marketplace add FlutterFlow/flutterflow-claude`) is the primary path;
  local-clone install is documented as the development/testing path, with the
  repo-root requirement for `marketplace add ./` spelled out and a troubleshooting
  note quoting the real CLI errors.

### Removed
- `mcp.example.json` — superseded by the CLI's per-workspace MCP
  auto-registration; its `command: "flutterflow"` launch shape risked breaking
  the MCP stdio handshake (the pub shim prints "Resolving dependencies…" to
  stdout when its snapshot is stale).

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

[Unreleased]: https://github.com/FlutterFlow/flutterflow-claude/compare/v0.1.6...HEAD
[0.1.6]: https://github.com/FlutterFlow/flutterflow-claude/releases/tag/v0.1.6
[0.1.5]: https://github.com/FlutterFlow/flutterflow-claude/releases/tag/v0.1.5
[0.1.4]: https://github.com/FlutterFlow/flutterflow-claude/releases/tag/v0.1.4
[0.1.3]: https://github.com/FlutterFlow/flutterflow-claude/releases/tag/v0.1.3
[0.1.2]: https://github.com/FlutterFlow/flutterflow-claude/releases/tag/v0.1.2
[0.1.1]: https://github.com/FlutterFlow/flutterflow-claude/compare/dac575b...3980e4b
