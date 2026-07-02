#!/usr/bin/env bash
# Security-property tests for session-start.sh.
#
# Runs the hook in a throwaway HOME and asserts the token-file lifecycle
# guarantees so they can't silently regress. Portable across macOS (BSD stat)
# and Linux (GNU stat). Exits non-zero if any assertion fails.
#
#   bash plugins/flutterflow/hooks/session-start.test.sh
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/session-start.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fails=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; fails=$((fails + 1)); }

# File permission bits, portable: GNU stat -c first, else BSD stat -f.
mode() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"; }

# A fake `flutterflow` on PATH makes the hook exit right after the token bridge,
# so no `dart pub global activate` is ever attempted regardless of the runner.
mkdir -p "$WORK/bin"
printf '#!/bin/sh\nexit 0\n' > "$WORK/bin/flutterflow"
chmod +x "$WORK/bin/flutterflow"

# run <HOME> <TOKEN> <stderr-file>
run() { HOME="$1" PATH="$WORK/bin:$PATH" CLAUDE_PLUGIN_OPTION_API_TOKEN="$2" bash "$HOOK" 2>"$3"; }

echo "== A: token set -> file 600, dir 700, both exports present =="
H="$WORK/A"; mkdir -p "$H"
run "$H" 'plainTOKEN123' "$WORK/a.log"
EF="$H/.config/flutterflow/claude-env.sh"
[ "$(mode "$EF")" = "600" ] && pass "env file mode 600" || fail "env file mode is $(mode "$EF"), want 600"
[ "$(mode "$H/.config/flutterflow")" = "700" ] && pass "config dir mode 700" || fail "config dir mode is $(mode "$H/.config/flutterflow"), want 700"
grep -q '^export FF_API_KEY=' "$EF" && grep -q '^export FLUTTERFLOW_API_TOKEN=' "$EF" \
  && pass "both FF_API_KEY and FLUTTERFLOW_API_TOKEN exported" || fail "missing an export"
grep -q '^# managed-by: flutterflow-claude plugin' "$EF" \
  && pass "hook-written file carries the managed-by marker" || fail "managed-by marker missing"

echo
echo "== B: token with shell metacharacters round-trips exactly (no injection) =="
H="$WORK/B"; mkdir -p "$H"
TRICKY='a$b`whoami`"c'\''d e'
run "$H" "$TRICKY" "$WORK/b.log"
GOT=$(env -i bash -c ". '$H/.config/flutterflow/claude-env.sh'; printf '%s' \"\$FF_API_KEY\"")
[ "$GOT" = "$TRICKY" ] && pass "metacharacter token round-trips via %q quoting" \
  || { fail "round-trip mismatch"; printf '  want=[%s]\n  got =[%s]\n' "$TRICKY" "$GOT"; }

echo
echo "== C: token cleared -> hook-managed file removed, hand-written file kept =="
H="$WORK/C"; mkdir -p "$H"
run "$H" 'stale-token' "$WORK/c0.log"   # hook writes a marker-stamped file
run "$H" '' "$WORK/c1.log"
[ ! -e "$H/.config/flutterflow/claude-env.sh" ] && pass "hook-managed key file removed on clear" \
  || fail "hook-managed key file still present after token cleared"

H="$WORK/C2"; mkdir -p "$H/.config/flutterflow"
printf 'export FF_API_KEY=usersown\n' > "$H/.config/flutterflow/claude-env.sh"
run "$H" '' "$WORK/c2.log"
[ -f "$H/.config/flutterflow/claude-env.sh" ] && pass "hand-written key file (no marker) preserved" \
  || fail "hand-written key file was deleted"
grep -q 'app.flutterflow.io/account' "$WORK/c2.log" \
  && fail "no-key notice shown despite a hand-written key file" \
  || pass "no-key notice suppressed when a hand-written key file provides the key"

H="$WORK/C3"; mkdir -p "$H/.config/flutterflow"
printf '# flutterflow-claude: user-provided key (clipboard hand-off)\nexport FF_API_KEY=fromclip\n' \
  > "$H/.config/flutterflow/claude-env.sh"
run "$H" '' "$WORK/c3.log"
[ -f "$H/.config/flutterflow/claude-env.sh" ] && pass "clipboard-script file (its own header) preserved" \
  || fail "clipboard-script file was deleted — header collides with the managed marker"

echo
echo "== D: env file is a symlink pointing outside -> target NOT written =="
H="$WORK/D"; mkdir -p "$H/.config/flutterflow"
OUT="$WORK/D_outside.txt"; printf 'ORIGINAL\n' > "$OUT"
ln -s "$OUT" "$H/.config/flutterflow/claude-env.sh"
run "$H" 'secretTOKEN' "$WORK/d.log"
grep -q 'secretTOKEN' "$OUT" && fail "SECRET LEAKED into symlink target" \
  || pass "leaf symlink not followed — outside target untouched"
EF="$H/.config/flutterflow/claude-env.sh"
{ [ -f "$EF" ] && [ ! -L "$EF" ] && [ "$(mode "$EF")" = "600" ]; } \
  && pass "fresh regular 600 file written in place" || fail "expected a fresh regular 600 file"

echo
echo "== E: config dir is a symlink -> refuse to write =="
H="$WORK/E"; mkdir -p "$H/.config"; mkdir -p "$WORK/E_real"
ln -s "$WORK/E_real" "$H/.config/flutterflow"
run "$H" 'secretTOKEN' "$WORK/e.log"
grep -rq 'secretTOKEN' "$WORK/E_real" 2>/dev/null && fail "wrote through symlinked config dir" \
  || pass "refused symlinked config dir"
grep -q 'symlink' "$WORK/e.log" && pass "logged refusal to stderr" || fail "no refusal logged"

echo
echo "== G: no token -> account link shown once, then throttled =="
H="$WORK/G"; mkdir -p "$H"
run "$H" '' "$WORK/g1.log"
grep -q 'app.flutterflow.io/account' "$WORK/g1.log" \
  && pass "no-key notice links to the account page" || fail "account link missing from notice"
run "$H" '' "$WORK/g2.log"
grep -q 'app.flutterflow.io/account' "$WORK/g2.log" \
  && fail "notice repeated within throttle window" || pass "notice throttled on the next run"

echo
echo "== F: HOME unset -> clean exit 0, no crash, no writes =="
if env -u HOME PATH="$WORK/bin:$PATH" CLAUDE_PLUGIN_OPTION_API_TOKEN=x bash "$HOOK" 2>/dev/null; then
  pass "exits 0 with HOME unset"
else
  fail "non-zero exit with HOME unset"
fi

echo
if [ "$fails" -eq 0 ]; then
  echo "All security-property tests passed."
else
  echo "$fails assertion(s) failed."
fi
exit $([ "$fails" -eq 0 ] && echo 0 || echo 1)
