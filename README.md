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

Install directly from this marketplace repo — two commands in Claude Code:

```text
/plugin marketplace add FlutterFlow/flutterflow-claude
/plugin install flutterflow@flutterflow
```

> `FlutterFlow/flutterflow-claude` is the public GitHub repo Claude Code clones.
> `flutterflow` after the `@` is the marketplace **name** (from
> `.claude-plugin/marketplace.json`), which matches the GitHub **org** name — not
> the repo (`flutterflow-claude`).

Once accepted into the [Claude plugin directory](https://claude.com/plugins-for/cowork),
the plugin is also discoverable by every Claude Code user through the built-in
`claude-plugins-official` marketplace (browse it with `/plugin`) — no
`marketplace add` step required.

On enable, Claude Code prompts for the **FlutterFlow API token**
(from <https://app.flutterflow.io/account>). On the next session start the CLI
installs itself; after that the hook is a fast pass that just refreshes your PATH
and the token file (no install work) — so a rotated token is picked up next session.

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
> dialog may not accept input
> ([#51538](https://github.com/anthropics/claude-code/issues/51538)) and `sensitive`
> values may not persist across restarts
> ([#62442](https://github.com/anthropics/claude-code/issues/62442)). If the dialog
> misbehaves, write `~/.config/flutterflow/claude-env.sh` from your own terminal (the
> build skill shows the exact command) or let `flutterflow ai init` prompt for the
> key. The hook only auto-removes `claude-env.sh` files it wrote itself (stamped with
> a `# managed-by:` first line) — a hand-written file is never deleted.

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

Then, inside Claude Code (these are slash commands, not shell commands), add this
repo as a marketplace from a local path and install:

```text
/plugin marketplace add /absolute/path/to/flutterflow-claude
/plugin install flutterflow@flutterflow
```

After editing the marketplace, users refresh with `/plugin marketplace update`.

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
