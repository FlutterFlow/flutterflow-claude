#!/usr/bin/env bash
# FlutterFlow AI — SessionStart hook
#
# Goal: make the `flutterflow` CLI available with zero user effort, and fail
# soft no matter what. Runs on every session start/resume; it is a fast no-op
# once the CLI is installed.
#
# It never exits non-zero (a failing SessionStart hook must not block a session).

set -o pipefail

log() { printf '[flutterflow] %s\n' "$1"; }

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
  mkdir -p "$ENV_DIR" 2>/dev/null
  # `flutterflow ai` authenticates with FF_API_KEY; FLUTTERFLOW_API_TOKEN is the
  # legacy export-code/deploy-firebase var. Write both, set to the same token.
  DESIRED="export FF_API_KEY=\"$TOKEN\"
export FLUTTERFLOW_API_TOKEN=\"$TOKEN\""
  if [ ! -f "$ENV_FILE" ] || [ "$(cat "$ENV_FILE" 2>/dev/null)" != "$DESIRED" ]; then
    printf '%s\n' "$DESIRED" > "$ENV_FILE"
    chmod 600 "$ENV_FILE" 2>/dev/null
  fi
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
  : > "$STAMP"

  log "Installing the FlutterFlow CLI (dart pub global activate flutterflow_cli)…"
  if dart pub global activate flutterflow_cli >"$STAMP_DIR/activate.log" 2>&1; then
    log "✓ FlutterFlow CLI installed — you're ready for agentic building."
    if ! command -v flutterflow >/dev/null 2>&1; then
      log "One more step: add Dart's pub-cache bin to your PATH, then restart:"
      log "  echo 'export PATH=\"\$HOME/.pub-cache/bin:\$PATH\"' >> ~/.zshrc"
    fi
  else
    log "✗ CLI install failed. See the log: $STAMP_DIR/activate.log"
    log "Open the FlutterFlow build skill for guided troubleshooting."
  fi
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
