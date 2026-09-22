#!/usr/bin/env bash
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/tests/testlib.sh"
GUARD="$ROOT/bin/shrink-guard.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/shrink-guard-test.XXXXXX")
trap 'rm -rf -- "$TMP"' EXIT

bytes() { dd if=/dev/zero bs=1 count="$1" 2>/dev/null | tr '\000' x; }
seed() { bytes "$2" > "$1"; }
size() { wc -c < "$1" | tr -d ' '; }
run() { OUT=$("$@" 2>&1); RC=$?; }

TARGET="$TMP/document with spaces.md"
seed "$TARGET" 1000
BEFORE=$(cksum < "$TARGET")
run bash "$GUARD" "$TARGET" < <(bytes 699)
is "below-threshold replacement is rejected" "$RC" 3
is "rejection leaves original bytes intact" "$(cksum < "$TARGET")" "$BEFORE"
has "rejection reports retained-size reason" "$OUT" "retained-size"
is "rejected candidate is saved" "$(find "$TMP" -name 'document with spaces.md.rejected-*' -type f | wc -l | tr -d ' ')" 1
has "rejection is written to target-local audit" "$(cat "$TARGET.shrink-guard.audit.tsv")" REJECT

seed "$TARGET" 1000
OLD_INODE=$(ls -di "$TARGET" | awk '{print $1}')
chmod 640 "$TARGET"
run bash "$GUARD" "$TARGET" < <(bytes 700)
is "exact threshold is accepted" "$RC" 0
is "accepted candidate has exact bytes" "$(size "$TARGET")" 700
NEW_INODE=$(ls -di "$TARGET" | awk '{print $1}')
[ "$OLD_INODE" != "$NEW_INODE" ] && ok "replacement uses a new same-directory inode" || bad "replacement uses a new same-directory inode" "different inode" "$NEW_INODE"
MODE=$(stat -f '%Lp' "$TARGET" 2>/dev/null) || MODE=$(stat -c '%a' "$TARGET")
is "existing target permissions are preserved" "$MODE" 640
is "no staging file remains" "$(find "$TMP" -name '.shrink-guard.*' | wc -l | tr -d ' ')" 0

seed "$TARGET" 1000
FORCE_LOG="$TMP/override audit.tsv"
run bash "$GUARD" --force --audit-log "$FORCE_LOG" --label "release tool" "$TARGET" < <(bytes 100)
is "--force overrides size rejection" "$RC" 0
is "forced bytes are installed" "$(size "$TARGET")" 100
has "forced override is audited" "$(cat "$FORCE_LOG")" FORCE-ALLOW
has "audit carries caller label" "$(cat "$FORCE_LOG")" "label=release tool"

seed "$TARGET" 1000
run bash "$GUARD" --force "$TARGET" < /dev/null
is "--force alone cannot install empty content" "$RC" 3
is "empty rejection preserves original" "$(size "$TARGET")" 1000
run bash "$GUARD" --force --allow-empty "$TARGET" < /dev/null
is "double explicit flags allow empty content" "$RC" 0
is "allowed empty content is installed" "$(size "$TARGET")" 0

seed "$TARGET" 1000
CHECK_LOG="$TMP/check.tsv"
run bash "$GUARD" --check --audit-log "$CHECK_LOG" "$TARGET" < <(bytes 50)
is "--check returns policy rejection" "$RC" 3
is "--check does not write target" "$(size "$TARGET")" 1000
[ ! -e "$CHECK_LOG" ] && ok "--check does not write audit" || bad "--check does not write audit" absent present

NEW="$TMP/new document.md"
CANDIDATE="$TMP/candidate file"
printf 'new content\n' > "$CANDIDATE"
run bash "$GUARD" --from "$CANDIDATE" "$NEW"
is "--from creates a new target" "$RC" 0
is "--from preserves candidate bytes" "$(cksum < "$NEW")" "$(cksum < "$CANDIDATE")"

run bash "$GUARD" --min-percent nope "$TARGET" < /dev/null
is "invalid percentage is a usage error" "$RC" 2
run bash "$GUARD" --allow-empty "$TARGET" < /dev/null
is "--allow-empty without --force is a usage error" "$RC" 2
run bash "$GUARD" --audit-log "$TARGET" "$TARGET" < <(printf x)
is "audit log cannot alias the protected target" "$RC" 2
run bash "$GUARD" "$TMP/missing/target.md" < <(printf x)
is "missing parent is an operational failure" "$RC" 1
ln -s "$TARGET" "$TMP/link.md"
run bash "$GUARD" "$TMP/link.md" < <(printf x)
is "symlink target is refused" "$RC" 2

seed "$TARGET" 1000
run bash "$GUARD" --check --min-percent 08 "$TARGET" < <(bytes 80)
is "zero-padded percentage is interpreted as decimal" "$RC" 0

mkdir "$TMP/wc-shim"
printf '#!/usr/bin/env bash\nexit 66\n' > "$TMP/wc-shim/wc"
chmod +x "$TMP/wc-shim/wc"
OUT=$(PATH="$TMP/wc-shim:$PATH" bash "$GUARD" --from "$CANDIDATE" "$TMP/must-not-be-created" 2>&1); RC=$?
is "candidate measurement failure exits operationally" "$RC" 1
[ ! -e "$TMP/must-not-be-created" ] && ok "measurement failure cannot install a new target" || bad "measurement failure cannot install a new target" absent present

mkdir "$TMP/checksum-shim" "$TMP/signal-buffers"
export REAL_CKSUM="$(command -v cksum)" SIGNAL_MARKER="$TMP/signal-paused"
cat > "$TMP/checksum-shim/cksum" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$$" > "$SIGNAL_MARKER"
kill -STOP "$$"
exec "$REAL_CKSUM" "$@"
SHIM
chmod +x "$TMP/checksum-shim/cksum"
seed "$CANDIDATE" 1000
BEFORE=$(cksum < "$TARGET")
PATH="$TMP/checksum-shim:$PATH" TMPDIR="$TMP/signal-buffers" bash "$GUARD" --check --from "$CANDIDATE" "$TARGET" >"$TMP/signal.out" 2>"$TMP/signal.err" & guard_pid=$!
for attempt in $(seq 1 200); do [ -s "$SIGNAL_MARKER" ] && break; sleep .01; done
if [ -s "$SIGNAL_MARKER" ]; then
  read -r paused_pid < "$SIGNAL_MARKER"
  kill -TERM "$guard_pid"
  kill -CONT "$paused_pid"
  wait "$guard_pid"; RC=$?
  is "TERM stops a paused check with signal exit status" "$RC" 143
  hasnt "signalled check cannot report PASS" "$(cat "$TMP/signal.out")" PASS
else
  bad "check reached signal regression barrier" present missing
  kill -TERM "$guard_pid" 2>/dev/null || :
  wait "$guard_pid" 2>/dev/null || :
fi
is "signalled check leaves original intact" "$(cksum < "$TARGET")" "$BEFORE"
is "signalled check removes its candidate buffer" "$(find "$TMP/signal-buffers" -type f | wc -l | tr -d ' ')" 0

finish
