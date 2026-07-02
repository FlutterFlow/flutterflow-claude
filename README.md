# FlutterFlow plugins for Claude Code

A Claude Code [plugin marketplace](https://code.claude.com/docs/en/plugin-marketplaces)
that gets FlutterFlow users set up for **agentic building** with as little friction
as possible.

It ships one plugin, **`flutterflow`**, which:

- **Auto-installs the FlutterFlow CLI** (`dart pub global activate flutterflow_cli`)
  on session start — and **handles a missing Dart SDK** by pointing the user at an
  install instead of failing silently.
- **Prompts for the API token** at enable time and stores it securely.
- Adds a **guided build skill** (workspace `init`, then orient → validate → apply)
  that drives `flutterflow ai` over the Bash tool (which reads your shell profile),
  sidestepping the GUI-environment / PATH issues that bite a GUI-launched MCP server.

## Prerequisites

The user must already have:

1. **Claude Code** installed and signed in (this can't be bootstrapped by a plugin).
2. **Git** (used by the marketplace install).
3. **Dart**, bundled with **Flutter** — required for the FlutterFlow CLI. If it's
   missing, the plugin detects it and links the install; nothing else breaks.

The SessionStart hook is a POSIX shell script run with `bash`, so **macOS and Linux
are supported out of the box**. On Windows it needs a `bash` on PATH (Git Bash or
WSL); without one the hook no-ops and you'd drive `flutterflow ai` manually.

## Install

**Primary path — install straight from GitHub, no clone needed.** Two slash
commands inside Claude Code:

```text
/plugin marketplace add FlutterFlow/flutterflow-claude
/plugin install flutterflow@flutterflow
```

Or the equivalent from any terminal (same result — the CLI and desktop app share
plugin state):

```bash
claude plugin marketplace add FlutterFlow/flutterflow-claude
claude plugin install flutterflow@flutterflow
```

> `FlutterFlow/flutterflow-claude` is the public GitHub repo Claude Code clones (an
> HTTPS URL works too). `flutterflow` after the `@` is the marketplace **name** (from
> `.claude-plugin/marketplace.json`), which matches the GitHub **org** name — not
> the repo (`flutterflow-claude`). Installs track the repo's default branch;
> `/plugin marketplace update flutterflow` pulls the latest.

Working from a local checkout instead (contributing or testing changes)? See
[Local development / testing](#local-development--testing) — GitHub install is the
right path for everyone else.

Once accepted into the [Claude plugin directory](https://claude.com/plugins-for/cowork),
the plugin is also discoverable by every Claude Code user through the built-in
`claude-plugins-official` marketplace (browse it with `/plugin`) — no
`marketplace add` step required.

After install, connect your **FlutterFlow API key**: copy it from
<https://app.flutterflow.io/account>, then tell Claude *"I copied my FlutterFlow API
key"* — the build skill stores it straight from your clipboard so it never enters
the chat (details in the note under
[How the token reaches the CLI](#how-the-token-reaches-the-cli)). On the next
session start the CLI installs itself; after that the hook is a fast pass that just
refreshes your PATH and the key file (no install work) — so a rotated key is picked
up next session.

## Using it

Ask Claude to build something in FlutterFlow — the **build** skill
(`/flutterflow:build`) triggers on FlutterFlow tasks. It first ensures you have a
workspace (`flutterflow ai init <name>`, required by every toolbox command), then
walks orient → validate → apply. Or invoke it explicitly.

Everything also works straight from a terminal: `flutterflow ai init my-app`,
`flutterflow ai status <project-id>`, `flutterflow ai inspect <project-id>`,
`flutterflow ai validate <file.dart>`, `flutterflow ai run <file.dart>`.

## How the token reaches the CLI

`flutterflow ai` authenticates with the **`FF_API_KEY`** environment variable (the
legacy `FLUTTERFLOW_API_TOKEN` only feeds `export-code`/`deploy-firebase`).
`userConfig` values are available to plugin subprocesses (like the SessionStart
hook) but **not** to the Bash tool that runs `flutterflow`. So the hook bridges it:
it reads the token from `CLAUDE_PLUGIN_OPTION_API_TOKEN` and writes
`~/.config/flutterflow/claude-env.sh` (dir `chmod 700`, file `chmod 600`) exporting
both `FF_API_KEY` and `FLUTTERFLOW_API_TOKEN`, which the build skill sources before
each command. If the token wasn't set at enable time, the skill guides you to set it
out-of-band (via `/plugin configure` or your own terminal) — never accepting it in
chat — and the hook writes the same file on the next session start.

> **Known upstream issues:** in current Claude Code versions the `/plugin configure`
> dialog does not accept input
> ([#73530](https://github.com/anthropics/claude-code/issues/73530)) and `sensitive`
> values may not persist across restarts
> ([#62442](https://github.com/anthropics/claude-code/issues/62442)). Until those are
> fixed, the build skill sets the key without the dialog: copy the key from
> <https://app.flutterflow.io/account> and tell Claude *"I copied my FlutterFlow API
> key"* — a bundled script ([`store-key-from-clipboard.sh`](plugins/flutterflow/scripts/store-key-from-clipboard.sh))
> reads the clipboard once, validates it, writes `~/.config/flutterflow/claude-env.sh`
> (0600), and clears the clipboard, so the key never enters the chat. Over
> SSH/headless, the skill gives a terminal one-liner instead, or let
> `flutterflow ai init` prompt for the key. The hook only auto-removes `claude-env.sh`
> files it wrote itself (stamped with a `# managed-by:` first line) — user-provided
> files are never deleted.

**Rotating or removing the token.** After updating it via `/plugin configure
flutterflow@flutterflow`, **restart the session** — the hook only rewrites
`claude-env.sh` on a new session start, so an already-running session keeps the old
key until then. To remove it entirely, delete the bridged file and clear the CLI's
cached credentials:

```bash
rm -f ~/.config/flutterflow/claude-env.sh
flutterflow ai logout --all   # clears ~/.flutterflow/credentials.json (bare `logout` only lists)
```

## Optional: native MCP instead of the CLI skill

Power users can run FlutterFlow's own MCP server instead. See
[`plugins/flutterflow/mcp.example.json`](plugins/flutterflow/mcp.example.json):
add `"mcpServers": "./mcp.example.json"` to the plugin manifest. The key is injected
as `FF_API_KEY` via `${user_config.api_token}` (resolved by Claude Code, so no shell
env is needed). Caveats: the `flutterflow` binary must be resolvable where Claude
Code launches the server (a GUI app may need an absolute command path), and the
server must run inside an initialized workspace (`flutterflow ai init`) — point
`--workspace` at it.

## Repo layout

```text
flutterflow-claude/
├── .claude-plugin/
│   └── marketplace.json              # marketplace catalog (repo root)
├── .github/
│   └── workflows/
│       └── ci.yml                    # manifest validation, lint, security tests
├── plugins/
│   └── flutterflow/
│       ├── .claude-plugin/
│       │   └── plugin.json           # plugin manifest
│       ├── hooks/
│       │   ├── hooks.json            # registers the SessionStart hook
│       │   ├── session-start.sh      # Dart-aware self-healing installer
│       │   └── session-start.test.sh # security-property tests for the hook
│       ├── skills/
│       │   └── build/
│       │       └── SKILL.md          # build workflow (init → orient → validate → apply)
│       └── mcp.example.json          # optional native-MCP path (off by default)
└── README.md
```

## Local development / testing

Validate the manifests and try it without publishing:

Validate the plugin manifest, skill frontmatter, and hooks.json from your shell:

```bash
claude plugin validate ./plugins/flutterflow --strict
```

Run the SessionStart hook's security-property tests (token file perms, safe
`%q` quoting, cleanup when the token is cleared, refusal to follow a symlinked
config dir). These also run in CI on every push and PR:

```bash
bash plugins/flutterflow/hooks/session-start.test.sh
```

Then register your clone as a local marketplace and install from it — this is the
**development/testing path**; end users should install from GitHub (see
[Install](#install)). From a terminal, **run it from the repo root** (the directory
containing `.claude-plugin/marketplace.json`):

```bash
cd /path/to/flutterflow-claude
claude plugin marketplace add ./
claude plugin install flutterflow@flutterflow
```

Inside Claude Code the same works as slash commands — there's no `cd`, so use the
absolute path: `/plugin marketplace add /absolute/path/to/flutterflow-claude`, then
`/plugin install flutterflow@flutterflow`.

Notes:

- The local marketplace registers under the same **name** (`flutterflow`) as the
  GitHub install — they can't coexist. Remove one before adding the other:
  `claude plugin marketplace remove flutterflow`.
- After editing plugin files, refresh the installed copy with
  `claude plugin marketplace update flutterflow` (or uninstall/reinstall).

> **Troubleshooting:** if `marketplace add .` fails with *"Invalid marketplace
> source format. Try: owner/repo, https://..., or ./path"*, bare `.` isn't an
> accepted source — write `./`. If `add ./` fails with *"Marketplace file not found
> at …/.claude-plugin/marketplace.json"*, you're not in the repo root — `cd` into
> the clone and re-run.

## Publishing & updates

This repo is public, so it can be installed directly (above) and submitted to the
[Claude plugin directory](https://claude.com/plugins-for/cowork) via the in-app forms
(Console: <https://platform.claude.com/plugins/submit>). Run `claude plugin validate`
before submitting.

After the plugin is published in the directory, **updates pushed to `main` are picked
up automatically** — the directory's CI mirrors changes and re-screens each update, so
you don't re-submit the form.

Bump `version` in `plugin.json` to ship an update — it is the single source of truth.
(Claude Code always reads the version from `plugin.json`; the marketplace entry
deliberately omits `version` so the two can't drift.)
