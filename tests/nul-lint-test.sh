#!/usr/bin/env bash
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/tests/testlib.sh"
LINT="$ROOT/bin/nul-lint.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/nul-lint-test.XXXXXX")
trap 'rm -rf -- "$TMP"' EXIT
REPO="$TMP/repo with spaces"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email test@example.invalid
git -C "$REPO" config user.name Test
run() { OUT=$(cd "$REPO" && bash "$LINT" "$@" 2>&1); RC=$?; }

printf 'clean\n' > "$REPO/good.md"
printf '#!/bin/sh\nexit 0\n' > "$REPO/tool.sh"
git -C "$REPO" add good.md tool.sh
git -C "$REPO" commit -qm base
run
is "clean tracked files exit zero" "$RC" 0
has "clean result is explicit" "$OUT" clean

printf 'before' > "$REPO/bad file.md"; printf '\000after\n' >> "$REPO/bad file.md"
git -C "$REPO" add "bad file.md"
run
is "tracked worktree NUL is found" "$RC" 3
has "space-containing path is preserved" "$OUT" "bad file.md"
has "first byte offset is reported" "$OUT" "byte 6"

git -C "$REPO" reset -q HEAD -- "bad file.md"
rm -f -- "$REPO/bad file.md"
printf 'clean staged base\n' > "$REPO/staged.sh"
git -C "$REPO" add staged.sh
git -C "$REPO" commit -qm staged-base
printf 'x\000y\n' > "$REPO/staged.sh"
git -C "$REPO" add staged.sh
printf 'clean worktree after index snapshot\n' > "$REPO/staged.sh"
run --staged
is "--staged reads the index blob" "$RC" 3
has "staged finding is labelled" "$OUT" staged
has "staged offset is byte one" "$OUT" "byte 1"

printf 'PNG\000data' > "$REPO/image.png"
git -C "$REPO" add image.png
run --staged
hasnt "binary extension is not reported" "$OUT" image.png

mkdir -p "$REPO/incoming files" "$REPO/elsewhere"
printf 'a\000b' > "$REPO/incoming files/note.md"
run
is "untracked files are opt-in" "$RC" 0
run --untracked-dir "incoming files"
is "configured untracked directory is scanned" "$RC" 3
has "untracked finding is labelled" "$OUT" untracked

printf 'x\000z' > "$REPO/elsewhere/custom.data"
run --path "elsewhere/custom.data" --extensions data
is "explicit path and custom extension are scanned" "$RC" 3
has "explicit path is labelled selected" "$OUT" selected
run --untracked --all-extensions --json
is "all untracked extensions can be scanned" "$RC" 3
printf '%s' "$OUT" | python3 -c 'import json,sys; assert json.load(sys.stdin)["count"] >= 2' \
  && ok "JSON output is parseable" || bad "JSON output is parseable" "valid JSON" "$OUT"

run --extensions 'md,$bad'
is "invalid extension is a usage error" "$RC" 2
run --staged --untracked
is "staged and untracked selectors cannot be mixed" "$RC" 2
OUT=$(cd "$REPO" && bash "$LINT" --path "$TMP" 2>&1); RC=$?
is "selected path outside repository is refused" "$RC" 2
OUT=$(cd "$TMP" && bash "$LINT" 2>&1); RC=$?
is "running outside Git is an operational failure" "$RC" 1

CONTROL=$'control\b\033.md'
UNICODE='café.md'
printf 'a\000b' > "$REPO/$CONTROL"
printf 'c\000d' > "$REPO/$UNICODE"
git -C "$REPO" add -- "$CONTROL" "$UNICODE"
run --json
is "control and Unicode filename findings retain exit three" "$RC" 3
printf '%s' "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); names=[f["file"] for f in d["findings"]]; assert "control\b\x1b.md" in names and "café.md" in names' \
  && ok "JSON filenames preserve backspace, ESC, and Unicode" || bad "JSON filenames preserve backspace, ESC, and Unicode" "valid exact JSON names" "$OUT"

cp -f "$REPO/.git/index" "$TMP/saved-index"
printf 'broken index' > "$REPO/.git/index"
run
is "failed Git tracked enumeration exits operationally" "$RC" 1
hasnt "failed enumeration cannot claim clean" "$OUT" 'clean;'
run --staged
is "failed Git staged enumeration exits operationally" "$RC" 1
cp -f "$TMP/saved-index" "$REPO/.git/index"

mkdir "$TMP/git-shim" "$TMP/find-shim"
export REAL_GIT="$(command -v git)"
cat > "$TMP/git-shim/git" <<'SHIM'
#!/usr/bin/env bash
if [ "${1:-}" = ls-files ] && [ "${2:-}" = --others ]; then exit 61; fi
exec "$REAL_GIT" "$@"
SHIM
printf '#!/usr/bin/env bash\nexit 62\n' > "$TMP/find-shim/find"
chmod +x "$TMP/git-shim/git" "$TMP/find-shim/find"
PATH="$TMP/git-shim:$PATH" run --untracked
is "failed Git untracked enumeration exits operationally" "$RC" 1
PATH="$TMP/find-shim:$PATH" run --path "incoming files"
is "failed explicit-directory traversal exits operationally" "$RC" 1
hasnt "failed traversal cannot claim clean" "$OUT" 'clean;'

printf 'outside\000secret' > "$TMP/outside.md"
ln -s "$TMP/outside.md" "$REPO/outside-link.md"
git -C "$REPO" add outside-link.md
run --json
hasnt "tracked symlinks do not read outside target content" "$OUT" outside-link.md
ln -s "incoming files" "$REPO/inside-link"
run --path inside-link/note.md
is "explicit path through a symlink ancestor is refused" "$RC" 2

run --extensions '.md'
is "dot-prefixed extension selectors scan the intended files" "$RC" 3
run --extensions '*'
is "extension selectors cannot expand shell glob patterns" "$RC" 2
run --path "$REPO" --extensions md
is "the absolute worktree root is a valid explicit directory" "$RC" 3

# A Git index can carry a raw-byte path even on filesystems that reject such names.
blob=$(printf 'u\000v' | git -C "$REPO" hash-object -w --stdin)
printf '100644 %s\tbad-\377.md\000' "$blob" | git -C "$REPO" update-index -z --index-info
OUT=$(cd "$REPO" && bash "$LINT" --staged --json 2>"$TMP/invalid-name.err"); RC=$?
is "invalid UTF-8 staged filename fails operationally" "$RC" 1
is "invalid UTF-8 staged filename emits no partial JSON" "$OUT" ''

finish
