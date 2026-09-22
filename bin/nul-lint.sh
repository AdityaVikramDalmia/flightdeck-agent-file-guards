#!/usr/bin/env bash
# Detect literal NUL bytes in Git-managed text files without trusting Git's binary heuristic.
set -uo pipefail

tool=nul-lint.sh
usage() {
  cat <<'EOF'
Usage: nul-lint.sh [options]

By default, scan tracked worktree files whose extensions are in the text list.

Options:
  --staged                 Scan added/copied/modified/renamed blobs in the Git index
  --untracked              Also scan all non-ignored untracked files
  --untracked-dir DIR      Also scan non-ignored untracked files below DIR (repeatable)
  --path PATH              Scan an explicit worktree file or directory (repeatable)
  --extensions LIST        Comma/space-separated extensions (default below)
  --all-extensions         Treat every regular file as text
  --json                   Emit one JSON result object
  --quiet                  Emit nothing when clean
  -h, --help               Show this help

Default extensions: md markdown txt text sh bash zsh fish py rb pl js mjs cjs ts tsx jsx
                    json jsonl yaml yml toml ini cfg conf xml html css csv tsv sql go rs java
Exit codes: 0 clean; 1 operational failure; 2 usage error; 3 NUL found.
EOF
}
usage_error() { printf '%s: %s\n' "$tool" "$*" >&2; exit 2; }
fail() { printf '%s: %s\n' "$tool" "$*" >&2; exit 1; }

command -v git >/dev/null 2>&1 || fail "missing dependency: git"
command -v perl >/dev/null 2>&1 || fail "missing dependency: perl"

mode=worktree
scan_untracked=0
json=0
quiet=0
all_extensions=0
extensions="${NUL_LINT_EXTENSIONS:-md markdown txt text sh bash zsh fish py rb pl js mjs cjs ts tsx jsx json jsonl yaml yml toml ini cfg conf xml html css csv tsv sql go rs java}"
declare -a untracked_dirs explicit_paths hit_paths hit_offsets hit_sets processed_paths
untracked_dirs=()
explicit_paths=()
hit_paths=()
hit_offsets=()
hit_sets=()
processed_paths=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --staged) mode=staged; shift ;;
    --untracked) scan_untracked=1; shift ;;
    --untracked-dir) [ "$#" -ge 2 ] || usage_error "--untracked-dir needs a directory"; untracked_dirs+=("$2"); shift 2 ;;
    --path) [ "$#" -ge 2 ] || usage_error "--path needs a path"; explicit_paths+=("$2"); shift 2 ;;
    --extensions) [ "$#" -ge 2 ] || usage_error "--extensions needs a list"; extensions=$2; shift 2 ;;
    --all-extensions) all_extensions=1; shift ;;
    --json) json=1; shift ;;
    --quiet) quiet=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage_error "unknown argument: $1" ;;
  esac
done

[ "$mode" = worktree ] || { [ "$scan_untracked" -eq 0 ] && [ "${#untracked_dirs[@]}" -eq 0 ] && [ "${#explicit_paths[@]}" -eq 0 ]; } \
  || usage_error "--staged cannot be combined with worktree/untracked path selectors"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "not inside a Git worktree"
repo=$(git rev-parse --show-toplevel) || fail "cannot resolve Git worktree root"
cd "$repo" || fail "cannot enter Git worktree root"

scratch=$(mktemp -d "${TMPDIR:-/tmp}/nul-lint.XXXXXX") || fail "cannot create path manifest directory"
manifest="$scratch/paths"
trap 'rm -rf -- "$scratch"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
enumerate() { "$@" > "$manifest" || fail "path enumeration failed: $1"; }
if [ "$json" -eq 1 ]; then
  perl -MEncode -MJSON::PP -e 1 || fail "JSON output requires Perl core Encode and JSON::PP"
fi

extensions=$(printf '%s' "$extensions" | tr ',\n\t[:upper:]' '   [:lower:]')
extension_items=()
IFS=' ' read -r -a extension_items <<< "$extensions"
[ "${#extension_items[@]}" -gt 0 ] || usage_error "--extensions needs a nonempty list"
extensions=
for ext in ${extension_items[@]+"${extension_items[@]}"}; do
  ext=${ext#.}
  case "$ext" in ''|*[!A-Za-z0-9_-]*) usage_error "invalid extension in --extensions: $ext" ;; esac
  extensions="$extensions $ext"
done

is_text() {
  [ "$all_extensions" -eq 1 ] && return 0
  path_ext=${1##*.}
  path_ext=$(printf '%s' "$path_ext" | tr '[:upper:]' '[:lower:]')
  case " $extensions " in *" $path_ext "*) return 0 ;; *) return 1 ;; esac
}
nul_file() { nul_stdin < "$1"; }
nul_stdin() { perl -0777 -ne 'my $i=index($_,chr(0)); print $i if $i>=0'; }

# Worktree scans never dereference Git symlinks or replaced directory ancestors.
# Explicit selectors report these as invalid; automatically enumerated links are skipped.
has_symlink_component() {
  local rest="$1" current="$repo" component
  case "$rest" in "$repo"/*) rest=${rest#"$repo"/} ;; esac
  while [ -n "$rest" ]; do
    component=${rest%%/*}; current="$current/$component"
    [ ! -L "$current" ] || return 0
    case "$rest" in */*) rest=${rest#*/} ;; *) break ;; esac
  done
  return 1
}

scanned=0
add_result() {
  f=$1 set_name=$2 offset=$3
  scanned=$((scanned + 1))
  [ -n "$offset" ] || return 0
  hit_paths+=("$f")
  hit_offsets+=("$offset")
  hit_sets+=("$set_name")
}
scan_worktree_stream() {
  set_name=$1
  while IFS= read -r -d '' f; do
    has_symlink_component "$f" && continue
    [ -f "$f" ] || continue
    [ ! "$f" -ef "$manifest" ] || continue
    is_text "$f" || continue
    duplicate=0
    for seen in ${processed_paths[@]+"${processed_paths[@]}"}; do [ "$seen" = "$f" ] && duplicate=1 && break; done
    [ "$duplicate" -eq 1 ] && continue
    processed_paths+=("$f")
    off=$(nul_file "$f") || fail "cannot scan: $f"
    add_result "$f" "$set_name" "$off"
  done
}

if [ "$mode" = staged ]; then
  enumerate git diff --cached --name-only --diff-filter=ACMR -z
  while IFS= read -r -d '' f; do
    is_text "$f" || continue
    off=$(git show ":./$f" 2>/dev/null | nul_stdin) || fail "cannot scan staged blob: $f"
    add_result "$f" staged "$off"
  done < "$manifest"
else
  enumerate git ls-files -z
  scan_worktree_stream tracked < "$manifest"
  if [ "$scan_untracked" -eq 1 ]; then
    enumerate git ls-files --others --exclude-standard -z
    scan_worktree_stream untracked < "$manifest"
  elif [ "${#untracked_dirs[@]}" -gt 0 ]; then
    for d in ${untracked_dirs[@]+"${untracked_dirs[@]}"}; do
      [ -d "$d" ] && [ ! -L "$d" ] || usage_error "untracked directory is not a real directory: $d"
      untracked_abs=$(cd "$d" 2>/dev/null && pwd -P) || usage_error "cannot resolve untracked directory: $d"
      case "$untracked_abs/" in "$repo/"|"$repo"/*) ;; *) usage_error "untracked directory is outside the Git worktree: $d" ;; esac
    done
    enumerate git ls-files --others --exclude-standard -z -- ${untracked_dirs[@]+"${untracked_dirs[@]}"}
    scan_worktree_stream untracked < "$manifest"
  fi
  for selected in ${explicit_paths[@]+"${explicit_paths[@]}"}; do
    [ -e "$selected" ] || usage_error "selected path does not exist: $selected"
    [ ! -L "$selected" ] || usage_error "selected path must not be a symlink: $selected"
    if [ -d "$selected" ]; then
      selected_parent=$(cd "$selected" 2>/dev/null && pwd -P) || usage_error "cannot resolve selected directory: $selected"
    else
      selected_parent=$(cd "$(dirname -- "$selected")" 2>/dev/null && pwd -P) || usage_error "cannot resolve selected path: $selected"
    fi
    case "$selected_parent/" in
      "$repo/"|"$repo"/*) ;;
      *) usage_error "selected path is outside the Git worktree: $selected" ;;
    esac
    has_symlink_component "$selected" && usage_error "selected path traverses a symlink: $selected"
    if [ -f "$selected" ]; then
      enumerate printf '%s\0' "$selected"
      scan_worktree_stream selected < "$manifest"
    elif [ -d "$selected" ]; then
      enumerate find "$selected" -type f -print0
      scan_worktree_stream selected < "$manifest"
    else
      usage_error "selected path is not a regular file or directory: $selected"
    fi
  done
fi

count=${#hit_paths[@]}
json_escape() {
  perl -MEncode -MJSON::PP -e '
    my $text = Encode::decode("UTF-8", $ARGV[0], Encode::FB_CROAK);
    my $quoted = JSON::PP->new->ascii->allow_nonref->encode($text);
    print substr($quoted, 1, length($quoted)-2);
  ' -- "$1"
}
if [ "$json" -eq 1 ]; then
  encoded_paths=()
  for f in ${hit_paths[@]+"${hit_paths[@]}"}; do
    encoded=$(json_escape "$f") || fail "cannot encode JSON filename: valid UTF-8 is required"
    encoded_paths+=("$encoded")
  done
  printf '{"mode":"%s","scanned":%d,"count":%d,"findings":[' "$mode" "$scanned" "$count"
  for ((i=0; i<count; i++)); do
    [ "$i" -eq 0 ] || printf ','
    printf '{"file":"%s","offset":%s,"set":"%s"}' \
      "${encoded_paths[$i]}" "${hit_offsets[$i]}" "${hit_sets[$i]}"
  done
  printf ']}\n'
elif [ "$count" -eq 0 ]; then
  [ "$quiet" -eq 1 ] || printf 'nul-lint: clean; scanned %d text file(s) [%s]\n' "$scanned" "$mode"
else
  printf 'nul-lint: %d text file(s) contain a literal NUL byte:\n' "$count"
  for ((i=0; i<count; i++)); do
    printf '  %s (%s): first NUL at byte %s\n' "${hit_paths[$i]}" "${hit_sets[$i]}" "${hit_offsets[$i]}"
  done
fi

[ "$count" -eq 0 ] && exit 0 || exit 3
