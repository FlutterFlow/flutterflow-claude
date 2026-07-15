---
name: build
description: "Agentic building with FlutterFlow via the `flutterflow ai` CLI. Use whenever the user wants to set up a FlutterFlow AI workspace or inspect, plan, change, or validate a FlutterFlow project — building pages/screens/components, editing app state or data types, wiring actions, or applying declarative Dart (DSL) changes. Also handles first-run setup — installing the CLI, configuring FF_API_KEY, and scaffolding a workspace with `flutterflow ai init`. Trigger on key hand-off phrases like \"I copied my FlutterFlow key\", \"copied my API key\", or \"copied\" right after key setup instructions."
---

# FlutterFlow agentic building

Drive a FlutterFlow project through the `flutterflow ai` CLI. Agents and humans
share the same surface, so every step here also works from a terminal.

`flutterflow ai` subcommands and flags evolve — when a flag is unclear, run
`flutterflow ai <command> --help` or `flutterflow ai docs [topic]` rather than guessing.

## 0. Preflight — run before any `flutterflow ai` command

Each Bash call starts fresh, so prefix commands with this preamble. It puts the CLI
on PATH and loads the API key:

```bash
export PATH="$HOME/.pub-cache/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
for d in "$HOME/flutter/bin" "$HOME/development/flutter/bin" "$HOME/fvm/default/bin" \
  "$HOME/.puro/envs/default/flutter/bin" /opt/flutter/bin /usr/local/flutter/bin; do
  [ -d "$d" ] && PATH="$d:$PATH"
done
export PATH
# Source the key file only if it's a regular, user-owned, non-symlink file — the
# preamble dot-sources it as shell, so refuse a planted symlink or foreign-owned file.
FF_ENV="$HOME/.config/flutterflow/claude-env.sh"
[ -f "$FF_ENV" ] && [ ! -L "$FF_ENV" ] && [ -O "$FF_ENV" ] && . "$FF_ENV"
```

Confirm readiness:

```bash
command -v flutterflow >/dev/null && echo "cli: ok" || echo "cli: MISSING"
[ -n "${FF_API_KEY:-}" ] && echo "key: ok" || echo "key: MISSING"
```

### If `cli: MISSING`
- `dart` available → `dart pub global activate flutterflow_cli`, then re-run the
  preamble. If `flutterflow` still isn't found, `~/.pub-cache/bin` isn't on PATH —
  use the preamble's `export PATH=…` (and suggest adding it to `~/.zshrc`).
- `dart` NOT available → Dart (bundled with Flutter) must be installed first:
  https://docs.flutter.dev/get-started/install. Don't install Flutter unasked.

### If `key: MISSING`
`flutterflow ai` authenticates with **`FF_API_KEY`**. If the user doesn't have a key
yet, point them to **https://app.flutterflow.io/account** to create one.

**Hard rules — the key must never enter the model context:**
- **Never ask the user to paste the key into the chat** or an AskUserQuestion field
  (chat is logged and retained). Tell them up front: *"Do NOT paste the key into
  this chat."* If a key-shaped string ever appears in chat anyway, treat it as
  compromised: do not use or store it, tell the user to rotate it immediately at
  https://app.flutterflow.io/account.
- **Never run `pbpaste`, `wl-paste`, `xclip`, `xsel`, or `Get-Clipboard` bare or in
  any pipeline you compose** — their stdout enters the model context. The ONLY
  sanctioned clipboard access is the bundled script below.
- **Never `cat`/Read/grep-with-output** `~/.config/flutterflow/claude-env.sh`,
  `~/.flutterflow/credentials.json`, or any `.flutterflow/.env`. Debug with
  presence checks only: `[ -n "${FF_API_KEY:-}" ]`, `ls -l`, `wc -c`.

Set the key via one of these paths, then re-run the preflight:

1. **Recommended (local desktop) — clipboard hand-off.** Tell the user:
   *"1) Open https://app.flutterflow.io/account and copy your API key. 2) Come back
   and just say **copied** — do NOT paste the key into this chat. I'll read your
   clipboard once, without displaying it, then clear it."*
   The moment they say "copied", IMMEDIATELY (no other tool calls in between) run
   exactly this as a standalone command:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/store-key-from-clipboard.sh"
   ```
   (If `CLAUDE_PLUGIN_ROOT` is unset in your Bash environment, resolve the script
   relative to this skill's base directory: `../../scripts/store-key-from-clipboard.sh`.)
   The script validates the clipboard, writes the env file (0600), clears the
   clipboard, and prints only a status line — the key never reaches this chat.
   - On `key: INVALID`, reply exactly: *"That didn't look like an API key — something
     may have overwritten your clipboard. Copy the key again (make it the last thing
     you copy) and say copied."*
   - On `clipboard: UNAVAILABLE` (SSH, headless, containers), fall back to path 2.
2. **SSH / headless / no clipboard — their own terminal:** the user runs this in
   THEIR terminal and types the key at the hidden prompt (never into this chat;
   `read -rs` also keeps it out of shell history):
   ```bash
   [ -L ~/.config/flutterflow ] && echo "refusing: symlink" || { \
     mkdir -p ~/.config/flutterflow && chmod 700 ~/.config/flutterflow && \
     bash -c 'umask 077; read -rsp "FlutterFlow API key: " K; echo; \
       printf "export FF_API_KEY=%q\nexport FLUTTERFLOW_API_TOKEN=%q\n" "$K" "$K" \
       > ~/.config/flutterflow/claude-env.sh'; }
   ```
3. **Let the CLI collect it:** in the user's own terminal, bare `flutterflow ai`
   (outside a workspace) launches an onboarding wizard — key prompt with echo off,
   then a searchable project picker. `flutterflow ai init <name> --project
   <project-id>` with no `FF_API_KEY` in the env prompts for the key too. Either
   way the key is cached (`~/.flutterflow/credentials.json` plus the workspace
   `.env`), so in-workspace commands authenticate without any env file.

The SessionStart hook never deletes user-provided key files — it only auto-removes
files it wrote itself (first line `# managed-by: flutterflow-claude plugin`).
Do NOT suggest `/plugin configure` for the key: its input dialog is broken upstream
(anthropics/claude-code#73530) and `sensitive` values don't persist (#62442). The
hook still bridges a configured token automatically if one exists.

If the first authenticated command later fails with 401/permission-denied, the key
is wrong or revoked — reply: *"FlutterFlow rejected that key. Copy a fresh one from
https://app.flutterflow.io/account and say copied — don't paste it here."*

Once the key is set (env file or cached credentials), `flutterflow ai init` runs
non-interactively.

## 1. Workspace — required before the toolbox

Every `flutterflow ai` toolbox command must run from **inside an initialized
workspace** — a directory containing `.flutterflow/config.yaml` (any subdirectory
works too; the CLI walks up to find the root). Check first:

```bash
[ -f .flutterflow/config.yaml ] && echo "workspace: ok" || echo "workspace: NONE"
```

If there's none, scaffold one. Ask the user for a workspace name, and whether they're
editing an **existing** project (its id is in the project URL:
https://app.flutterflow.io/project/<id>) or starting a **new** app:

```bash
flutterflow ai init <name> --project <project-id>   # existing project
flutterflow ai init <name>                          # new app — created on first `run`
cd <name>
```

This runs non-interactively: `--project` (when given) binds the project up front and
the key comes from `FF_API_KEY` in the env (`--resume` re-enters an existing scaffold;
the target path must be new or empty, or init fast-fails). Don't
pass the key on the command line (e.g. `--api-key`) — that puts the secret into a Bash
invocation and the model context; rely on `FF_API_KEY` from the sourced env file.
`init` writes `.flutterflow/.env` with `FF_API_KEY`
and `FF_DSL_PROJECT_ID`, so later commands in this workspace are authenticated and
project-scoped. See `flutterflow ai init --help` for more (`--env`, `--sdk-path`,
`--pre-release`, `--no-save`, `--yes`).

**Existing project, but no id?** Newer CLIs (> 0.0.38) list the account's projects
non-interactively — names and ids aren't secrets, so this is safe to show in chat:

```bash
flutterflow ai projects --json [--match <text>]
```

stdout is exactly one JSON array of `{id, name, isLibrary, lastEditMillis}`,
most recently edited first (notices go to stderr). Offer the top few as an
AskUserQuestion — one option per project (name + id in the description, since
names can repeat) plus a "create a new app" option — and let Other capture a
name or id to fuzzy-match against the full list, re-asking only when ambiguous.
If the command fails (older CLI — outside a workspace it exits with "No
FlutterFlow AI workspace found"), fall back to asking for the project URL.

`init` also scaffolds guidance **inside the workspace** — `CLAUDE.md`, `AGENTS.md`,
`references/`, `patterns/` (managed files; `refresh-workspace` overwrites them) —
and auto-registers the FlutterFlow MCP server with detected agents, including a
project-scoped `.mcp.json` for Claude Code. A session rooted in the workspace may
therefore offer `flutterflow_ai` MCP tools alongside this skill; both drive the
same project state, so use whichever is available. Follow the workspace's own
CLAUDE.md where it adds specifics.

## 2. Orient — read before you write

The read commands take the project id as a positional argument:

- `flutterflow ai status <project-id>` — remote project state (pages, components,
  collections, app state). For local SDK/workspace health use `doctor` / `context-check` instead.
- `flutterflow ai inspect <project-id> [--page <name>|--component <name>] [--outline] [--tree] [--dsl-json] [--max-depth <N>] [--output <file>]` — structure of the project or a specific page/component. (Scope is chosen with flags, not a positional.)
- `flutterflow ai resources <project-id> [--library <name>] [--match <text>]` — list pages/components/types.
- `flutterflow ai search <project-id> --query <text>` — find by name or visible text (`-q` works too).
- `flutterflow ai doctor` / `flutterflow ai context-check` — local diagnostics.
- `flutterflow ai docs [topic]` — DSL and command docs from the terminal.
- `flutterflow ai upgrade --check` — SDK freshness as `key: value` lines (last line
  `newer_available: true|false`). The workspace guidance asks agents to run this once
  per session and offer `flutterflow ai upgrade` when a newer build exists.

If `context-check` reports STALE: `flutterflow ai refresh-context <project-id>`.

## 3. Author → validate → apply

Changes are declarative Dart (DSL) files. Learn the DSL with `flutterflow ai docs`.

- **Validate (dry run):** `flutterflow ai validate <file.dart>` — checks the change without applying it.
- **Apply:** `flutterflow ai run <file.dart> [--commit-message "<text>"] [--find-or-create]`.

Both take the DSL file as a positional. Always validate before run, and show the
user the output; don't apply blind.

## 4. Audit / record

- `flutterflow ai plan save <file>` | `plan save --content "<text>"` | `plan show` | `plan clear` — stores/echoes YOUR intent in `.flutterflow/plan.md` (it does not generate a plan).
- `flutterflow ai trace latest` | `trace show <run-id>` | `trace export <run-id> [--out <file>]`.
- `flutterflow ai history [--all] [--limit <N>]` | `history show <run-id>`.

## 5. Branches & merges

The active branch is tracked in `.flutterflow/config.yaml`, and `run`/`validate`
target it automatically.

- `flutterflow ai branch list | current | status` — list branches / print the active
  one / compare local head against the server tip.
- `flutterflow ai branch create <name> [--from <commit-id>] [--include-uncommitted] [--checkout]`.
- `flutterflow ai branch checkout <name> [--force]` — switches the workspace
  (regenerates `generated_code/`; refuses on a dirty tree without `--force`).
- `flutterflow ai branch close <name>` / `branch restore <name>` — soft-delete
  (30-day window) / restore.
- `flutterflow ai merge start --from <branch> --into <branch>` — server-side
  three-way merge; the bundle materializes under `.flutterflow/merges/<id>/` and you
  edit `working/` directly. Then: `merge status`, `merge explain <file> [--json]`,
  `merge auto`, `merge resolve <file>`, `merge verify` (no-loss check),
  `merge commit -m "<msg>"` (refuses while drops exist unless `--accept-drops`),
  `merge abort`.

Other surfaces exist too (`codegen`, `test`, `test-pilot`, `issue`, `support`,
`upgrade`, `refresh-workspace`, `precache`, `create-project`, `mcp`, `logout`) —
use `--help`.

## Gotchas
- **Write project URLs with the scheme.** When telling the user where a project
  lives (after `init`, `create-project`, etc.), always write the full
  `https://app.flutterflow.io/project/<id>` — a schemeless `app.flutterflow.io/…`
  renders as plain text in chat, not a clickable link.
- **Auth var is `FF_API_KEY`**, not `FLUTTERFLOW_API_TOKEN`. The same account-page
  token works for both; the plugin sets both, but `flutterflow ai` reads only `FF_API_KEY`.
- **Workspace required.** Toolbox commands fail (exit 1, "No FlutterFlow AI
  workspace found from …") outside an initialized workspace — run
  `flutterflow ai init` first. Inside one, usage errors exit 64.
- **project-id is required** on status/inspect/resources/search; it is not inferred
  from the directory for these read commands.
- **PATH:** `dart pub global activate` installs to `~/.pub-cache/bin`; use the
  preamble or add it to `~/.zshrc`.
- **GUI vs shell env:** running via Bash (this skill) reads your shell profile and
  the token file; a GUI-launched MCP server may not — which is why this skill drives the CLI.
- **Credential cache:** `flutterflow ai init` caches the key in
  `~/.flutterflow/credentials.json` only when it was typed at the prompt or passed
  via `--api-key`; keys from `FF_API_KEY` (this skill's path) are never persisted.
  `flutterflow ai logout --all` clears the cache.
