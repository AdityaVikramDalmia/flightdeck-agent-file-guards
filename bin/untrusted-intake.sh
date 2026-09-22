#!/usr/bin/env bash
# Statically inventory agent instructions, hooks, and configuration in a checkout.
set -uo pipefail

tool=untrusted-intake.sh
usage() {
  cat <<'EOF'
Usage: untrusted-intake.sh [options] CHECKOUT

Read selected agent instruction/configuration surfaces without executing checkout code.

Options:
  --json                 Emit one JSON result object
  --max-bytes N          Do not content-scan a carrier larger than N bytes (default: 1048576)
  --include-git-hooks    Include non-sample files below .git/hooks
  -h, --help             Show this help

Exit codes: 0 no carriers found; 1 operational failure; 2 usage error; 3 findings.
This is a narrow static triage tool, not a security or malware certification.
EOF
}
usage_error() { printf '%s: %s\n' "$tool" "$*" >&2; exit 2; }
fail() { printf '%s: %s\n' "$tool" "$*" >&2; exit 1; }

json=0
max_bytes=1048576
include_git_hooks=0
target=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --json) json=1; shift ;;
    --max-bytes) [ "$#" -ge 2 ] || usage_error "--max-bytes needs a value"; max_bytes=$2; shift 2 ;;
    --include-git-hooks) include_git_hooks=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) usage_error "unknown option: $1" ;;
    *) [ -z "$target" ] || usage_error "only one CHECKOUT may be supplied"; target=$1; shift ;;
  esac
done
[ -n "$target" ] || usage_error "missing CHECKOUT (try --help)"
case "$max_bytes" in ''|*[!0-9]*) usage_error "--max-bytes must be a positive integer" ;; esac
[ "$max_bytes" -gt 0 ] || usage_error "--max-bytes must be a positive integer"
[ -d "$target" ] || usage_error "CHECKOUT is not a directory: $target"
root=$(cd -P "$target" 2>/dev/null && printf '%s.' "$PWD") || fail "cannot resolve CHECKOUT: $target"
root=${root%.}

scratch=$(mktemp -d "${TMPDIR:-/tmp}/untrusted-intake.XXXXXX") || fail "cannot create path manifest directory"
manifest="$scratch/paths"
trap 'rm -rf -- "$scratch"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
enumerate() { "$@" > "$manifest" || fail "path enumeration failed: $1"; }
if [ "$json" -eq 1 ]; then
  command -v perl >/dev/null 2>&1 || fail "JSON output requires Perl"
  perl -MEncode -MJSON::PP -e 1 || fail "JSON output requires Perl core Encode and JSON::PP"
fi

declare -a classes paths details carriers
classes=(); paths=(); details=(); carriers=()
add() {
  classes+=("$1")
  paths+=("$2")
  details+=("$3")
}
relative() {
  case "$1" in "$root") relative_path=. ;; "$root"/*) relative_path=${1#"$root"/} ;; *) relative_path=$1 ;; esac
}
# Check every component, including missing/broken final symlinks. A known nested
# surface such as .cursor/rules must not follow a symlink at .cursor.
no_symlink() {
  local rest="${1#"$root"/}" current="$root" component description="$2"
  while [ -n "$rest" ]; do
    component=${rest%%/*}; current="$current/$component"
    if [ -L "$current" ]; then
      add SYMLINK "$current" "$description is a symlink; target content was not read"
      return 1
    fi
    case "$rest" in */*) rest=${rest#*/} ;; *) break ;; esac
  done
  return 0
}
add_file() {
  local path=$1 description=$2
  no_symlink "$path" "$description" || return 0
  if [ -f "$path" ]; then
    add CARRIER "$path" "$description"
    carriers+=("$path")
  fi
}
add_tree() {
  local dir=$1 description=$2 found=0 path
  no_symlink "$dir" "$description" || return 0
  [ -d "$dir" ] || return 0
  enumerate find "$dir" \( -type f -o -type l \) -print0
  while IFS= read -r -d '' path; do
    found=1
    add_file "$path" "$description"
  done < "$manifest"
  [ "$found" -eq 1 ] || add CARRIER "$dir" "$description (empty directory)"
}

# Basename carriers may occur at any depth because nested instruction files can take effect.
enumerate find "$root" \
  \( -path "$root/.git" -o -path "$root/node_modules" -o -path "$root/vendor" \) -prune -o \
  \( -name AGENTS.md -o -name CLAUDE.md -o -name GEMINI.md -o -name SKILL.md \) \
  \( -type f -o -type l \) -print0
while IFS= read -r -d '' path; do
  add_file "$path" "agent instruction file"
done < "$manifest"

# Known configuration directories and exact files. find does not follow symlinks.
for dir in \
  "$root/.claude" "$root/.codex" "$root/.agents" "$root/.cursor/rules" \
  "$root/.windsurf/rules" "$root/.github/instructions" "$root/.github/hooks"
do
  add_tree "$dir" "agent configuration surface"
done
for file in \
  "$root/.mcp.json" "$root/mcp.json" "$root/.vscode/mcp.json" \
  "$root/.github/copilot-instructions.md" "$root/.cursor/rules.json"
do
  add_file "$file" "agent configuration file"
done
if [ "$include_git_hooks" -eq 1 ] && no_symlink "$root/.git/hooks" "Git hooks directory" && [ -d "$root/.git/hooks" ]; then
  enumerate find "$root/.git/hooks" -maxdepth 1 \( -type f -o -type l \) -print0
  while IFS= read -r -d '' path; do
    case "$path" in *.sample) continue ;; esac
    add_file "$path" "Git hook"
  done < "$manifest"
fi

# Deduplicate carrier reads. Presence rows may overlap when a named instruction sits in a
# configuration directory; duplicate findings are intentionally collapsed at output time.
declare -a scanned_carriers
scanned_carriers=()
already_scanned() {
  needle=$1
  for seen in ${scanned_carriers[@]+"${scanned_carriers[@]}"}; do [ "$seen" = "$needle" ] && return 0; done
  return 1
}
indicator_re='ignore (all )?(the )?(previous|prior|above)|disregard (all|the|previous)|you are now|new instructions|system prompt|<system|run the following|curl[^|]*\|[[:space:]]*(ba)?sh|wget[^|]*\|[[:space:]]*(ba)?sh|exfiltrat|BEGIN[- ]?INJECTION|mcpServers|hooks?[[:space:]]*:'
for path in ${carriers[@]+"${carriers[@]}"}; do
  already_scanned "$path" && continue
  scanned_carriers+=("$path")
  size=$(wc -c < "$path" 2>/dev/null | tr -d ' ') || fail "cannot read carrier metadata: $path"
  if [ "$size" -gt "$max_bytes" ]; then
    add UNSCANNED "$path" "carrier is ${size} bytes, above --max-bytes ${max_bytes}"
    continue
  fi
  grep_status=0
  hit=$(LC_ALL=C grep -a -nEi -m 1 "$indicator_re" "$path" | LC_ALL=C tr '\000' '?') || grep_status=$?
  [ "$grep_status" -le 1 ] || fail "cannot scan carrier content: $path"
  if [ -n "$hit" ]; then
    hit=${hit//$'\t'/ }; hit=${hit//$'\r'/ }; hit=${hit//$'\n'/ }
    if [ "$json" -eq 1 ]; then
      hit=$(printf '%s' "$hit" | perl -MEncode -0777 -ne '
        my $text=Encode::decode("UTF-8", $_, Encode::FB_CROAK);
        print Encode::encode("UTF-8", substr($text,0,180));
      ') || fail "cannot encode JSON indicator: valid UTF-8 is required"
    else
      hit=${hit:0:180}
    fi
    add INDICATOR "$path" "static review indicator: $hit"
  fi
done

# Collapse identical class/path rows while preserving first-seen order.
declare -a out_classes out_paths out_details
out_classes=(); out_paths=(); out_details=()
for ((i=0; i<${#classes[@]}; i++)); do
  duplicate=0
  for ((j=0; j<${#out_classes[@]}; j++)); do
    if [ "${classes[$i]}" = "${out_classes[$j]}" ] && [ "${paths[$i]}" = "${out_paths[$j]}" ]; then
      duplicate=1
      break
    fi
  done
  [ "$duplicate" -eq 1 ] && continue
  out_classes+=("${classes[$i]}")
  out_paths+=("${paths[$i]}")
  out_details+=("${details[$i]}")
done
count=${#out_classes[@]}

json_escape() {
  perl -MEncode -MJSON::PP -e '
    my $text = Encode::decode("UTF-8", $ARGV[0], Encode::FB_CROAK);
    my $quoted = JSON::PP->new->ascii->allow_nonref->encode($text);
    print substr($quoted, 1, length($quoted)-2);
  ' -- "$1"
}
if [ "$json" -eq 1 ]; then
  encoded_root=$(json_escape "$root") || fail "cannot encode JSON target: valid UTF-8 is required"
  encoded_paths=(); encoded_details=()
  for ((i=0; i<count; i++)); do
    relative "${out_paths[$i]}"
    encoded=$(json_escape "$relative_path") || fail "cannot encode JSON path: valid UTF-8 is required"
    encoded_paths+=("$encoded")
    encoded=$(json_escape "${out_details[$i]}") || fail "cannot encode JSON detail: valid UTF-8 is required"
    encoded_details+=("$encoded")
  done
  verdict=clean; [ "$count" -eq 0 ] || verdict=findings
  printf '{"target":"%s","verdict":"%s","findings_count":%d,"findings":[' "$encoded_root" "$verdict" "$count"
  for ((i=0; i<count; i++)); do
    [ "$i" -eq 0 ] || printf ','
    printf '{"class":"%s","path":"%s","detail":"%s"}' \
      "${out_classes[$i]}" "${encoded_paths[$i]}" "${encoded_details[$i]}"
  done
  printf '],"scope":"static agent instruction/config triage; not a security or malware certification"}\n'
elif [ "$count" -eq 0 ]; then
  printf 'untrusted-intake: CLEAN; no known agent instruction/config carriers found in %s\n' "$root"
  printf 'This static result is not a security or malware certification.\n'
else
  printf 'untrusted-intake: %d finding(s) in %s\n' "$count" "$root"
  for ((i=0; i<count; i++)); do
    relative "${out_paths[$i]}"
    printf '  %-10s %s — %s\n' "${out_classes[$i]}" "$relative_path" "${out_details[$i]}"
  done
  printf 'Review these files as data. This tool executed none of them.\n'
  printf 'This narrow static scan is not a security or malware certification.\n'
fi

[ "$count" -eq 0 ] && exit 0 || exit 3
