---
name: build
description: "Agentic building with FlutterFlow via the `flutterflow ai` CLI. Use whenever the user wants to set up a FlutterFlow AI workspace or inspect, plan, change, or validate a FlutterFlow project — building pages/screens/components, editing app state or data types, wiring actions, or applying declarative Dart (DSL) changes. Also handles first-run setup — installing the CLI, configuring FF_API_KEY, and scaffolding a workspace with `flutterflow ai init`."
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
yet, point them to **https://app.flutterflow.io/account** to create one. Treat the key
as a secret: **never ask the user to paste it into the chat** (that routes it through
the model context, where it's logged and retained), and never echo or commit it.
Instead, tell the user to set it via one of these secure, out-of-band paths, then
re-run the preflight:

1. **Recommended — keychain:** run `/plugin configure flutterflow@flutterflow` in
   Claude Code and enter the key in the masked field. Claude Code stores it securely
   (in the OS keychain where available) and the plugin's SessionStart hook bridges it to `FF_API_KEY` next session.
2. **Their own terminal:** the user adds the export themselves, so the key is typed
   into their shell — never into this conversation:
   ```bash
   mkdir -p ~/.config/flutterflow && chmod 700 ~/.config/flutterflow
   # the user runs this in THEIR terminal, pasting their own key. Wrapped in
   # `bash -c` because %q is a bash builtin — a plain `sh`/dash prompt drops it.
   #   bash -c 'umask 077; printf "export FF_API_KEY=%q\nexport FLUTTERFLOW_API_TOKEN=%q\n" "$1" "$1" \
   #     > ~/.config/flutterflow/claude-env.sh' _ "$KEY"
   ```

Once the key is set (keychain or env), `flutterflow ai init` runs non-interactively.

## 1. Workspace — required before the toolbox

Every `flutterflow ai` toolbox command must run from **inside an initialized
workspace** (a directory containing `.flutterflow/config.yaml`). Check first:

```bash
[ -f .flutterflow/config.yaml ] && echo "workspace: ok" || echo "workspace: NONE"
```

If there's none, scaffold one. Ask the user for a workspace name and their
FlutterFlow project id (it's in the project URL: https://app.flutterflow.io/project/<id>):

```bash
flutterflow ai init <name> --project <project-id>
cd <name>
```

This runs non-interactively: `--project` selects the project up front and the key
comes from `FF_API_KEY` in the env (`--resume` re-enters an existing scaffold). Don't
pass the key on the command line (e.g. `--api-key`) — that puts the secret into a Bash
invocation and the model context; rely on `FF_API_KEY` from the sourced env file.
`init` writes `.flutterflow/.env` with `FF_API_KEY`
and `FF_DSL_PROJECT_ID`, so later commands in this workspace are authenticated and
project-scoped. See `flutterflow ai init --help` for more (`--env`, `--sdk-path`,
`--pre-release`, `--no-save`).

## 2. Orient — read before you write

The read commands take the project id as a positional argument:

- `flutterflow ai status <project-id>` — remote project state (pages, components,
  collections, app state). For local SDK/workspace health use `doctor` / `context-check` instead.
- `flutterflow ai inspect <project-id> [--page <name>|--component <name>] [--outline] [--tree] [--dsl-json] [--max-depth <N>] [--output <file>]` — structure of the project or a specific page/component. (Scope is chosen with flags, not a positional.)
- `flutterflow ai resources <project-id> [--library <name>] [--match <text>]` — list pages/components/types.
- `flutterflow ai search <project-id> --query <text>` — find by name or visible text (`-q` works too).
- `flutterflow ai doctor` / `flutterflow ai context-check` — local diagnostics.
- `flutterflow ai docs [topic]` — DSL and command docs from the terminal.

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

Other surfaces exist too (`codegen`, `branch`, `merge`, `support`, `upgrade`,
`refresh-workspace`, `precache`, `create-project`, `logout`) — use `--help`.

## Gotchas
- **Write project URLs with the scheme.** When telling the user where a project
  lives (after `init`, `create-project`, etc.), always write the full
  `https://app.flutterflow.io/project/<id>` — a schemeless `app.flutterflow.io/…`
  renders as plain text in chat, not a clickable link.
- **Auth var is `FF_API_KEY`**, not `FLUTTERFLOW_API_TOKEN`. The same account-page
  token works for both; the plugin sets both, but `flutterflow ai` reads only `FF_API_KEY`.
- **Workspace required.** Toolbox commands fail (exit 64 / "No .flutterflow/config.yaml")
  outside an initialized workspace — run `flutterflow ai init` first.
- **project-id is required** on status/inspect/resources/search; it is not inferred
  from the directory for these read commands.
- **PATH:** `dart pub global activate` installs to `~/.pub-cache/bin`; use the
  preamble or add it to `~/.zshrc`.
- **GUI vs shell env:** running via Bash (this skill) reads your shell profile and
  the token file; a GUI-launched MCP server may not — which is why this skill drives the CLI.
- **Credential cache:** `flutterflow ai init` also caches the key in
  `~/.flutterflow/credentials.json`; `flutterflow ai logout` clears it.
