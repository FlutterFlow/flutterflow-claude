#!/usr/bin/env bash
# store-key-from-clipboard.sh — one-shot secure hand-off of the FlutterFlow API
# key from the OS clipboard to ~/.config/flutterflow/claude-env.sh.
#
# Invoked VERBATIM by the build skill. Agents must never compose clipboard
# reads inline: a bare `pbpaste` puts its stdout into retained model context.
# Inside this script the key never enters argv, a shell variable, a command
# substitution, or stdout/stderr — it moves clipboard → 0600 tmpfile →
# validated → env file, by redirection only, and the clipboard is read
# exactly once (no TOCTOU between validate and store).
#
# Output is exactly one status line (plus a fixed caveat on success):
#   key: STORED (clipboard cleared)
#   key: INVALID — <content-free class>
#   clipboard: UNAVAILABLE — <fixed reason>
#
# FF_CLIPBOARD_FILE: test-only override — read from this user-owned regular
# file instead of the clipboard (used by store-key-from-clipboard.test.sh).

{ set +x; } 2>/dev/null   # defeat inherited xtrace: it would expand redirections to stderr
umask 077
set -o pipefail

ok()           { printf 'key: STORED (clipboard cleared)\n'; printf 'note: clipboard-history managers (Raycast, Alfred, Win+V, Universal Clipboard) may still retain a copy — purge that entry if you use one.\n'; }
fail_invalid() { printf 'key: INVALID — %s\n' "$1" >&2; exit 1; }
fail_unavail() { printf 'clipboard: UNAVAILABLE — %s\n' "$1" >&2; exit 1; }

[ -n "${HOME:-}" ] || fail_unavail "HOME is not set"

# --- choose the clipboard source -------------------------------------------
# Absolute paths where the OS guarantees them (defeats exported-function or
# PATH shadowing); explicit CLIPBOARD selection on X11 (PRIMARY holds the last
# selection, not the copy); timeouts because xclip/xsel hang without a server.
MODE=""
if [ -n "${FF_CLIPBOARD_FILE:-}" ]; then
  { [ -f "$FF_CLIPBOARD_FILE" ] && [ ! -L "$FF_CLIPBOARD_FILE" ] && [ -O "$FF_CLIPBOARD_FILE" ]; } \
    || fail_unavail "test override is not a user-owned regular file"
  MODE="testfile"
elif [ -n "${SSH_CONNECTION:-}${SSH_TTY:-}" ]; then
  # A remote clipboard is the wrong machine's clipboard; route to the one-liner.
  fail_unavail "remote (SSH) session — run the terminal one-liner instead"
else
  case "$(uname -s)" in
    Darwin)
      [ -x /usr/bin/pbpaste ] && MODE="pbpaste"
      ;;
    Linux)
      if [ -n "${WAYLAND_DISPLAY:-}" ] && command -v wl-paste >/dev/null 2>&1; then MODE="wlpaste"
      elif [ -n "${DISPLAY:-}" ] && command -v xclip >/dev/null 2>&1; then MODE="xclip"
      elif [ -n "${DISPLAY:-}" ] && command -v xsel  >/dev/null 2>&1; then MODE="xsel"
      elif grep -qi microsoft /proc/version 2>/dev/null && command -v powershell.exe >/dev/null 2>&1; then MODE="wsl"
      fi
      ;;
  esac
fi
[ -n "$MODE" ] || fail_unavail "no local clipboard tool found — run the terminal one-liner instead"

read_clipboard() {
  case "$MODE" in
    testfile) cat "$FF_CLIPBOARD_FILE" ;;
    pbpaste)  /usr/bin/pbpaste ;;
    wlpaste)  wl-paste --no-newline ;;
    xclip)    timeout 5 xclip -selection clipboard -o ;;
    xsel)     timeout 5 xsel --clipboard --output ;;
    wsl)      powershell.exe -NoProfile -Command Get-Clipboard ;;
  esac
}

clear_clipboard() {
  case "$MODE" in
    testfile) : ;;  # never touch the real clipboard from tests
    pbpaste)  /usr/bin/pbcopy </dev/null 2>/dev/null ;;
    wlpaste)  wl-copy --clear 2>/dev/null ;;
    xclip)    printf '' | timeout 5 xclip -selection clipboard 2>/dev/null
              printf '' | timeout 5 xclip -selection primary   2>/dev/null ;;
    xsel)     timeout 5 xsel --clipboard --clear 2>/dev/null
              timeout 5 xsel --primary   --clear 2>/dev/null ;;
    wsl)      printf '' | clip.exe 2>/dev/null ;;
  esac
  return 0
}

# --- destination dir (symlink-hostile, mirrors session-start.sh) ------------
ENV_DIR="$HOME/.config/flutterflow"
ENV_FILE="$ENV_DIR/claude-env.sh"
[ -L "$ENV_DIR" ] && fail_unavail "refusing: $ENV_DIR is a symlink"
mkdir -p "$ENV_DIR" 2>/dev/null
chmod 700 "$ENV_DIR" 2>/dev/null

TMP="$(mktemp "$ENV_DIR/.clip.XXXXXX")" || fail_unavail "cannot create a temp file"
trap 'rm -f "$TMP" "$TMP.key" "$TMP.env"' EXIT

# --- single read, then validate the FILE (key never enters a variable) ------
read_clipboard > "$TMP" 2>/dev/null || fail_unavail "clipboard read failed"

NONEMPTY="$(grep -c . "$TMP" 2>/dev/null || true)"
[ "${NONEMPTY:-0}" -eq 0 ] && fail_invalid "clipboard was empty"
[ "$NONEMPTY" -gt 1 ]      && fail_invalid "clipboard held multiple lines"

# Normalize: first non-empty line, minus CR and surrounding whitespace,
# written WITHOUT a trailing newline so it can be spliced after 'export K='.
grep -m1 . "$TMP" | tr -d '\r' \
  | awk '{gsub(/^[ \t]+|[ \t]+$/, ""); printf "%s", $0}' > "$TMP.key"

# Strict allowlist BEFORE writing: the env file is later dot-sourced by the
# build-skill preflight, so this is the injection gate, and the charset (no
# quotes, spaces, $, backticks) is what makes unquoted splicing safe.
# FlutterFlow API keys are UUIDs (8-4-4-4-12 hex).
grep -qE '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' "$TMP.key" \
  || fail_invalid "contents don't match the API key format (expected a UUID)"

# --- assemble and install atomically ----------------------------------------
# First line is deliberately NOT the hook's '# managed-by: flutterflow-claude
# plugin' marker — session-start.sh auto-deletes marker-stamped files whenever
# no plugin token is configured, which would log clipboard users out nightly.
{
  printf '# flutterflow-claude: user-provided key (clipboard hand-off)\n'
  printf 'export FF_API_KEY='
  cat "$TMP.key"
  printf '\nexport FLUTTERFLOW_API_TOKEN='
  cat "$TMP.key"
  printf '\n'
} > "$TMP.env"

# Never write through a pre-planted symlink or non-regular file.
if [ -L "$ENV_FILE" ] || { [ -e "$ENV_FILE" ] && [ ! -f "$ENV_FILE" ]; }; then
  rm -f "$ENV_FILE" 2>/dev/null || fail_unavail "cannot replace existing $ENV_FILE"
fi
chmod 600 "$TMP.env" 2>/dev/null
mv -f "$TMP.env" "$ENV_FILE" || fail_unavail "cannot write $ENV_FILE"

clear_clipboard
ok
exit 0
