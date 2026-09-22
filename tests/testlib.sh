#!/usr/bin/env bash
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); printf 'ok %d - %s\n' "$PASS" "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'not ok - %s\n  expected: %s\n  actual: %s\n' "$1" "$2" "$3"; }
is() { [ "$2" = "$3" ] && ok "$1" || bad "$1" "$3" "$2"; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "contains $3" "$2" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1" "does not contain $3" "$2" ;; *) ok "$1" ;; esac; }
finish() {
  printf '1..%d\n' "$((PASS + FAIL))"
  printf '# %d passed, %d failed\n' "$PASS" "$FAIL"
  [ "$FAIL" -eq 0 ]
}
