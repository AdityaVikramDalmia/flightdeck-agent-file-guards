#!/usr/bin/env bash
# Guard a file replacement using the candidate's retained byte percentage.
set -uo pipefail

tool="shrink-guard.sh"
usage() {
  cat <<'EOF'
Usage: shrink-guard.sh [options] TARGET

Read replacement content from standard input and install it only if it passes.

Options:
  --check                Print the verdict without writing, logging, or saving a reject
  --from FILE            Read the candidate from FILE instead of standard input
  --min-percent N        Require at least N percent of the old byte count (default: 70)
  --force                Override only the retained-size check
  --allow-empty          Allow empty/whitespace content; requires --force
  --audit-log FILE       Audit reject/override events (default: TARGET.shrink-guard.audit.tsv)
  --no-audit             Disable audit logging explicitly
  --discard-rejected     Do not save a rejected candidate beside TARGET
  --label TEXT           Add caller context to the audit row
  -h, --help             Show this help

Exit codes: 0 accepted; 1 operational failure; 2 usage error; 3 policy rejection.
EOF
}
usage_error() { printf '%s: %s\n' "$tool" "$*" >&2; exit 2; }
fail() { printf '%s: %s\n' "$tool" "$*" >&2; exit 1; }
now_iso() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

mode=write
source_file=
min_percent="${SHRINK_GUARD_MIN_PERCENT:-70}"
force=0
allow_empty=0
audit_log=
audit_enabled=1
keep_rejected=1
label=
target=

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check) mode=check; shift ;;
    --from) [ "$#" -ge 2 ] || usage_error "--from needs a file"; source_file=$2; shift 2 ;;
    --min-percent) [ "$#" -ge 2 ] || usage_error "--min-percent needs a value"; min_percent=$2; shift 2 ;;
    --force) force=1; shift ;;
    --allow-empty) allow_empty=1; shift ;;
    --audit-log) [ "$#" -ge 2 ] || usage_error "--audit-log needs a file"; audit_log=$2; shift 2 ;;
    --no-audit) audit_enabled=0; shift ;;
    --discard-rejected) keep_rejected=0; shift ;;
    --label) [ "$#" -ge 2 ] || usage_error "--label needs a value"; label=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; [ "$#" -gt 0 ] || usage_error "missing TARGET after --"; break ;;
    -*) usage_error "unknown option: $1" ;;
    *) [ -z "$target" ] || usage_error "only one TARGET may be supplied"; target=$1; shift ;;
  esac
done
while [ "$#" -gt 0 ]; do
  [ -z "$target" ] || usage_error "only one TARGET may be supplied"
  target=$1
  shift
done

[ -n "$target" ] || usage_error "missing TARGET (try --help)"
case "$min_percent" in ''|*[!0-9]*) usage_error "--min-percent must be an integer from 0 to 100" ;; esac
[ "$min_percent" -le 100 ] || usage_error "--min-percent must be an integer from 0 to 100"
min_percent=$((10#$min_percent))
[ "$allow_empty" -eq 0 ] || [ "$force" -eq 1 ] || usage_error "--allow-empty requires --force"
[ -z "$source_file" ] || [ -f "$source_file" ] || usage_error "candidate is not a regular file: $source_file"
[ ! -d "$target" ] || usage_error "TARGET is a directory: $target"
[ ! -L "$target" ] || usage_error "refusing a symlink TARGET: $target"

target_dir=$(dirname -- "$target")
[ -d "$target_dir" ] || fail "TARGET parent does not exist: $target_dir"
[ -n "$audit_log" ] || audit_log="${target}.shrink-guard.audit.tsv"
if [ "$audit_enabled" -eq 1 ]; then
  [ "$audit_log" != "$target" ] || usage_error "audit log must not be TARGET"
  if [ -e "$audit_log" ] && [ -e "$target" ] && [ "$audit_log" -ef "$target" ]; then
    usage_error "audit log resolves to TARGET"
  fi
fi

candidate=$(mktemp "${TMPDIR:-/tmp}/shrink-guard.candidate.XXXXXX") || fail "cannot create candidate buffer"
stage=
cleanup() {
  rm -f -- "$candidate"
  [ -z "$stage" ] || rm -f -- "$stage"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
if [ -n "$source_file" ]; then
  cp -- "$source_file" "$candidate" || fail "cannot read candidate: $source_file"
else
  cat > "$candidate" || fail "cannot buffer candidate from standard input"
fi

new_bytes=$(wc -c < "$candidate" | tr -d ' ') || fail "cannot measure candidate"
new_nonspace=$(LC_ALL=C tr -d '[:space:]' < "$candidate" | wc -c | tr -d ' ') || fail "cannot measure candidate content"
old_bytes=0
old_fingerprint=missing
if [ -e "$target" ]; then
  [ -f "$target" ] || usage_error "TARGET is not a regular file: $target"
  old_bytes=$(wc -c < "$target" | tr -d ' ') || fail "cannot measure TARGET"
  old_fingerprint=$(cksum < "$target") || fail "cannot checksum TARGET: $target"
fi

kept_percent=100
if [ "$old_bytes" -gt 0 ]; then kept_percent=$((new_bytes * 100 / old_bytes)); fi

safe_field() { printf '%s' "$1" | tr '\t\r\n' '   '; }
audit() {
  event=$1
  note=$2
  [ "$audit_enabled" -eq 1 ] || return 0
  audit_dir=$(dirname -- "$audit_log")
  [ -d "$audit_dir" ] || mkdir -p -- "$audit_dir" || return 1
  printf '%s\t%s\ttarget=%s\told=%s\tnew=%s\tkept=%s%%\tfloor=%s%%\tlabel=%s\tnote=%s\n' \
    "$(now_iso)" "$event" "$(safe_field "$target")" "$old_bytes" "$new_bytes" \
    "$kept_percent" "$min_percent" "$(safe_field "${label:--}")" "$(safe_field "$note")" \
    >> "$audit_log"
}

save_reject() {
  [ "$mode" = write ] || return 0
  [ "$keep_rejected" -eq 1 ] || return 0
  rejected="${target}.rejected-$(date -u '+%Y%m%dT%H%M%SZ')-$$"
  cp -- "$candidate" "$rejected" || {
    printf '%s: warning: could not save rejected candidate beside TARGET\n' "$tool" >&2
    return 0
  }
  printf '%s: rejected candidate saved at %s\n' "$tool" "$rejected" >&2
}

reject() {
  reason=$1
  if [ "$mode" = check ]; then
    printf 'REJECT %s: %s (old=%s new=%s kept=%s%% floor=%s%%)\n' "$target" "$reason" "$old_bytes" "$new_bytes" "$kept_percent" "$min_percent"
  else
    audit REJECT "$reason" || printf '%s: warning: could not append audit log %s\n' "$tool" "$audit_log" >&2
    save_reject
    printf '%s: REJECTED %s: %s; original left untouched\n' "$tool" "$target" "$reason" >&2
  fi
  exit 3
}

if [ "$new_nonspace" -eq 0 ] && ! { [ "$force" -eq 1 ] && [ "$allow_empty" -eq 1 ]; }; then
  reject "candidate is empty or whitespace-only; use --force --allow-empty together to override"
fi

forced_size=0
if [ "$old_bytes" -gt 0 ] && [ $((new_bytes * 100)) -lt $((old_bytes * min_percent)) ]; then
  if [ "$force" -eq 1 ]; then
    forced_size=1
  else
    reject "candidate is below the retained-size threshold"
  fi
fi

if [ "$mode" = check ]; then
  if [ "$forced_size" -eq 1 ]; then
    printf 'PASS forced %s (old=%s new=%s kept=%s%% floor=%s%%)\n' "$target" "$old_bytes" "$new_bytes" "$kept_percent" "$min_percent"
  else
    printf 'PASS %s (old=%s new=%s kept=%s%% floor=%s%%)\n' "$target" "$old_bytes" "$new_bytes" "$kept_percent" "$min_percent"
  fi
  exit 0
fi

if [ "$forced_size" -eq 1 ] || [ "$new_nonspace" -eq 0 ]; then
  audit FORCE-ALLOW "explicit override accepted" || fail "cannot record required override audit at $audit_log"
fi

stage=$(mktemp "$target_dir/.shrink-guard.XXXXXX") || fail "cannot create same-directory staging file"
if [ -e "$target" ]; then
  cp -p -- "$target" "$stage" || fail "cannot preserve TARGET metadata on staging file"
fi
cat "$candidate" > "$stage" || fail "cannot write staging file"

# This comparison narrows, but cannot eliminate, the race with another writer. There is no lock.
if [ "$old_fingerprint" = missing ]; then
  [ ! -e "$target" ] || fail "TARGET appeared while the candidate was being checked; refusing to overwrite"
else
  [ -f "$target" ] && [ ! -L "$target" ] || fail "TARGET type changed while the candidate was being checked"
  current_fingerprint=$(cksum < "$target") || fail "cannot re-check TARGET before replacement"
  [ "$current_fingerprint" = "$old_fingerprint" ] || fail "TARGET changed while the candidate was being checked; refusing to overwrite"
fi

mv -f -- "$stage" "$target" || fail "cannot atomically replace TARGET"
stage=
if [ "$forced_size" -eq 1 ] || [ "$new_nonspace" -eq 0 ]; then
  if [ "$audit_enabled" -eq 1 ]; then
    printf '%s: override installed; authorization audited at %s\n' "$tool" "$audit_log" >&2
  else
    printf '%s: override installed; audit explicitly disabled by --no-audit\n' "$tool" >&2
  fi
fi
exit 0
