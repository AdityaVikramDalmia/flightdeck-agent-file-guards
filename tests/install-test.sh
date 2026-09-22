#!/usr/bin/env bash
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/tests/testlib.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/guards-install.XXXXXX")
trap 'rm -rf -- "$TMP"' EXIT
OUT=$(make -C "$ROOT" install "DESTDIR=$TMP/staging directory" PREFIX=/opt/guards 2>&1); RC=$?
is "install creates the destination directory" "$RC" 0
for command in shrink-guard nul-lint untrusted-intake; do
  OUT=$("$TMP/staging directory/opt/guards/bin/$command" --help 2>&1); RC=$?
  is "installed $command runs without repository-relative files" "$RC" 0
done
finish
