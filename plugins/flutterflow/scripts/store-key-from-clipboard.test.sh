#!/usr/bin/env bash
# Security-property tests for store-key-from-clipboard.sh.
#
# Uses FF_CLIPBOARD_FILE (the script's test-only source override) so the real
# clipboard is never read or cleared. Asserts the leak-freedom and lifecycle
# guarantees the design review made binding. Exits non-zero on any failure.
#
#   bash plugins/flutterflow/scripts/store-key-from-clipboard.test.sh
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/store-key-from-clipboard.sh"
HOOK="$HERE/../hooks/session-start.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fails=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; fails=$((fails + 1)); }
mode() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"; }

KEY="f54aaaaa-1111-2222-3333-444455556666"

# run <HOME> <clipfile> <outfile> — captures stdout+stderr together
run() { HOME="$1" FF_CLIPBOARD_FILE="$2" bash "$SCRIPT" >"$3" 2>&1; }

echo "== A: valid key -> stored, 600, sources correctly, never printed =="
H="$WORK/A"; mkdir -p "$H"
printf '%s\n' "$KEY" > "$WORK/a.clip"
run "$H" "$WORK/a.clip" "$WORK/a.out"; RC=$?
EF="$H/.config/flutterflow/claude-env.sh"
[ "$RC" -eq 0 ] && pass "exit 0 on valid key" || fail "exit $RC on valid key"
[ -f "$EF" ] && [ "$(mode "$EF")" = "600" ] && pass "env file written with mode 600" || fail "env file missing or wrong mode"
GOT=$(env -i bash -c ". '$EF'; printf '%s' \"\$FF_API_KEY\"")
[ "$GOT" = "$KEY" ] && pass "sourcing yields the exact key" || fail "sourced key mismatch"
grep -q "$KEY" "$WORK/a.out" && fail "KEY LEAKED into script output" || pass "key absent from script output"
grep -q 'key: STORED' "$WORK/a.out" && pass "fixed STORED status printed" || fail "STORED status missing"

echo
echo "== B: header is NOT the hook's managed marker; hook must not delete it =="
head -1 "$EF" | grep -q '^# managed-by: flutterflow-claude plugin' \
  && fail "header collides with the hook's auto-delete marker" \
  || pass "header distinct from the hook marker"
mkdir -p "$WORK/bin"; printf '#!/bin/sh\nexit 0\n' > "$WORK/bin/flutterflow"; chmod +x "$WORK/bin/flutterflow"
HOME="$H" PATH="$WORK/bin:$PATH" CLAUDE_PLUGIN_OPTION_API_TOKEN='' bash "$HOOK" 2>/dev/null
[ -f "$EF" ] && pass "hook (no token) preserves the clipboard-stored file" \
  || fail "hook deleted the clipboard-stored file"

echo
echo "== C: messy-but-valid clipboards are normalized =="
H="$WORK/C"; mkdir -p "$H"
printf '  %s\r\n\n' "$KEY" > "$WORK/c.clip"   # padding, CRLF, trailing blank line
run "$H" "$WORK/c.clip" "$WORK/c.out" \
  && GOT=$(env -i bash -c ". '$H/.config/flutterflow/claude-env.sh'; printf '%s' \"\$FF_API_KEY\"") \
  && [ "$GOT" = "$KEY" ] && pass "whitespace/CRLF trimmed to exact key" || fail "normalization failed"

echo
echo "== D: invalid clipboards -> nothing written, content never echoed =="
H="$WORK/D"; mkdir -p "$H"
printf '' > "$WORK/d1.clip"
run "$H" "$WORK/d1.clip" "$WORK/d1.out" && fail "empty clipboard accepted" || pass "empty clipboard rejected"
printf 'line one\nline two\n' > "$WORK/d2.clip"
run "$H" "$WORK/d2.clip" "$WORK/d2.out" && fail "multi-line accepted" || pass "multi-line clipboard rejected"
SECRET='hunter2 with spaces $(rm -rf ~) `boom`'
printf '%s\n' "$SECRET" > "$WORK/d3.clip"
run "$H" "$WORK/d3.clip" "$WORK/d3.out" && fail "shell-metachar content accepted" || pass "non-key content rejected"
printf 'ghp_abcdefghij1234567890abcdefghij123456\n' > "$WORK/d4.clip"   # key-length but not a UUID
run "$H" "$WORK/d4.clip" "$WORK/d4.out" && fail "non-UUID token accepted" || pass "non-UUID token (e.g. foreign PAT) rejected"
grep -qF 'hunter2' "$WORK/d1.out" "$WORK/d2.out" "$WORK/d3.out" 2>/dev/null \
  && fail "REJECTED CONTENT LEAKED into output" || pass "rejected content never echoed"
[ -e "$H/.config/flutterflow/claude-env.sh" ] && fail "env file written despite rejection" \
  || pass "nothing written on rejection"
ls "$H/.config/flutterflow/".clip.* 2>/dev/null | grep -q . \
  && fail "temp file left behind" || pass "no temp files left behind"

echo
echo "== E: symlinked config dir -> refuse =="
H="$WORK/E"; mkdir -p "$H/.config" "$WORK/E_real"
ln -s "$WORK/E_real" "$H/.config/flutterflow"
printf '%s\n' "$KEY" > "$WORK/e.clip"
run "$H" "$WORK/e.clip" "$WORK/e.out" && fail "wrote through symlinked dir" || pass "refused symlinked config dir"
grep -rq "$KEY" "$WORK/E_real" 2>/dev/null && fail "KEY LEAKED through symlink" || pass "symlink target untouched"

echo
echo "== F: leak-freedom static checks on the script itself =="
grep -nE '\$\((pbpaste|wl-paste|xclip|xsel|powershell)' "$SCRIPT" >/dev/null \
  && fail "clipboard read via command substitution (variable capture)" \
  || pass "no command-substitution clipboard reads"
grep -nE '\$\(\s*(cat|head|tail|awk|sed)\b[^)]*TMP|\$\(<' "$SCRIPT" >/dev/null \
  && fail "key file read via command substitution (enters argv/variables)" \
  || pass "key file never read into a variable or argv"

echo
if [ "$fails" -eq 0 ]; then echo "All clipboard-script tests passed."; else echo "$fails assertion(s) failed."; fi
exit $([ "$fails" -eq 0 ] && echo 0 || echo 1)
