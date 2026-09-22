#!/usr/bin/env bash
set -eu

# Example: generate to stdout while shrink-guard owns the only write to the target.
target=${1:?usage: guarded-write.sh TARGET}
script_dir=$(cd "$(dirname "$0")" && pwd)

generate_document() {
  printf '# Generated document\n\n'
  printf 'Generated at %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}

generate_document | "$script_dir/../bin/shrink-guard.sh" --min-percent 75 "$target"
