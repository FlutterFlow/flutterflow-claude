#!/usr/bin/env bash
# FlutterFlow AI — SessionStart hook
#
# Goal: make the `flutterflow` CLI available with zero user effort, and fail
# soft no matter what. Runs on every session start/resume; it is a fast no-op
# once the CLI is installed.
#
# It never exits non-zero (a failing SessionStart hook must not block a session).

set -o pipefail

# Human-facing notices go to stderr: SessionStart stdout is added to Claude's
# context, and these banners/instructions are meant for the user, not the model.
log() { printf '[flutterflow] %s\n' "$1" >&2; }

# Without HOME we can't locate the config/cache dirs and would operate on
# filesystem-root paths (/.config, /.pub-cache/bin). Bail cleanly instead.
if [ -z "${HOME:-}" ]; then
  log "HOME is not set — skipping FlutterFlow setup this session."
  exit 0
fi

# Pin the CLI version so this auto-run hook never floats to an unreviewed
# 'latest' from pub.dev. Bump deliberately alongside the plugin version.
FF_CLI_VERSION="0.0.37"

# -----------------------------------------------------------------------------
# 1. Make common Dart / Flutter / pub-cache bin dirs visible.
#    A GUI-launched Claude Code may not inherit your interactive shell PATH,
#    so we add the usual locations explicitly before probing for binaries.
# -----------------------------------------------------------------------------
export PATH="$HOME/.pub-cache/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
for d in \
  "$HOME/flutter/bin" \
  "$HOME/development/flutter/bin" \
  "$HOME/fvm/default/bin" \
  "$HOME/.puro/envs/default/flutter/bin" \
  "/opt/flutter/bin" \
  "/usr/local/flutter/bin"; do
  [ -d "$d" ] && export PATH="$d:$PATH"
done

# -----------------------------------------------------------------------------
# 2. Bridge the API token to the CLI.
#    userConfig values reach plugin subprocesses (like this hook) as
#    CLAUDE_PLUGIN_OPTION_*, but the Bash tool that later runs `flutterflow`
#    does NOT. So persist it to a file the skill sources before each command.
#    If the option isn't set, do nothing — the skill collects it interactively.
# -----------------------------------------------------------------------------
TOKEN="${CLAUDE_PLUGIN_OPTION_API_TOKEN:-}"
ENV_DIR="$HOME/.config/flutterflow"
ENV_FILE="$ENV_DIR/claude-env.sh"
if [ -n "$TOKEN" ]; then
  # Refuse to operate through a symlinked config dir: a pre-planted symlink could
  # redirect the plaintext token to a git-tracked/synced/attacker-readable path.
  if [ -L "$ENV_DIR" ]; then
    log "Refusing to write the token: $ENV_DIR is a symlink."
  else
    # Create the dir/file with tight perms from the outset (umask 077) so the
    # plaintext token is never momentarily group/world-readable.
    ( umask 077; mkdir -p "$ENV_DIR" 2>/dev/null )
    chmod 700 "$ENV_DIR" 2>/dev/null
    # If the target is a symlink or any non-regular file, remove it first so the
    # write below can't follow a link out to another location.
    if [ -L "$ENV_FILE" ] || { [ -e "$ENV_FILE" ] && [ ! -f "$ENV_FILE" ]; }; then
      rm -f "$ENV_FILE" 2>/dev/null
    fi
    # `flutterflow ai` authenticates with FF_API_KEY; FLUTTERFLOW_API_TOKEN is the
    # legacy export-code/deploy-firebase var. Write both, set to the same token.
    # %q shell-quotes the value so a token containing a quote, $, backtick, or
    # space is safe when the build skill sources this file (matches SKILL.md).
    DESIRED=$(printf 'export FF_API_KEY=%q\nexport FLUTTERFLOW_API_TOKEN=%q' "$TOKEN" "$TOKEN")
    if [ ! -f "$ENV_FILE" ] || [ "$(cat "$ENV_FILE" 2>/dev/null)" != "$DESIRED" ]; then
      ( umask 077; printf '%s\n' "$DESIRED" > "$ENV_FILE" )
    fi
    # Enforce perms on every run (not just on rewrite) so a pre-existing file with
    # loose permissions is always re-secured.
    chmod 600 "$ENV_FILE" 2>/dev/null
  fi
else
  # Token cleared in /plugin configure — remove the bridged plaintext copy so
  # clearing the config also revokes the on-disk key. (The CLI's own cached
  # credentials in ~/.flutterflow/credentials.json still need `flutterflow ai logout`.)
  [ -f "$ENV_FILE" ] && rm -f "$ENV_FILE" 2>/dev/null
fi

# -----------------------------------------------------------------------------
# 3. Already installed? Nothing more to do.
# -----------------------------------------------------------------------------
if command -v flutterflow >/dev/null 2>&1; then
  exit 0
fi

STAMP_DIR="$HOME/.cache/flutterflow-claude"
mkdir -p "$STAMP_DIR" 2>/dev/null

# -----------------------------------------------------------------------------
# 4. Not installed. Branch on whether Dart is available.
#    The dart/flutterflow probes are cheap and run every session, so the moment
#    a user installs Dart and restarts, the install kicks in. Only the network
#    install attempt and the "missing Dart" notice are throttled.
# -----------------------------------------------------------------------------
if command -v dart >/dev/null 2>&1; then
  # Throttle install attempts to once / 6h so repeated failures don't slow every
  # session start with a network/compile cycle.
  STAMP="$STAMP_DIR/last-install-attempt"
  if [ -n "$(find "$STAMP" -mmin -360 2>/dev/null)" ]; then
    exit 0
  fi

  log "Installing the FlutterFlow CLI (flutterflow_cli $FF_CLI_VERSION)…"
  if dart pub global activate flutterflow_cli "$FF_CLI_VERSION" >"$STAMP_DIR/activate.log" 2>&1; then
    log "✓ FlutterFlow CLI installed — you're ready for agentic building."
    if ! command -v flutterflow >/dev/null 2>&1; then
      log "One more step: add Dart's pub-cache bin to your PATH, then restart:"
      log "  echo 'export PATH=\"\$HOME/.pub-cache/bin:\$PATH\"' >> ~/.zshrc"
    fi
  else
    log "✗ CLI install failed. See the log: $STAMP_DIR/activate.log"
    log "Open the FlutterFlow build skill for guided troubleshooting."
  fi
  # Stamp only after a completed attempt (success or clean failure). If the
  # activate is interrupted (session quit, sleep, network drop) we don't stamp,
  # so the next session retries instead of no-opping for 6h.
  : > "$STAMP"
else
  # Dart missing — point the user at an install, throttled to once / 12h.
  STAMP="$STAMP_DIR/last-dart-notice"
  if [ -n "$(find "$STAMP" -mmin -720 2>/dev/null)" ]; then
    exit 0
  fi
  : > "$STAMP"

  log "The FlutterFlow CLI isn't installed, and the Dart SDK wasn't found."
  log "Dart (bundled with Flutter) is required for agentic building:"
  log "  • Flutter (recommended): https://docs.flutter.dev/get-started/install"
  log "  • Dart only:             https://dart.dev/get-dart"
  log "Then restart this session — the CLI installs itself automatically."
fi

exit 0
