# Agent File Guards

> **Deprecated for new Claude Code integrations — 2026-09-22.** Retained as an
> Apache-2.0 public reference implementation. This is a maintainer status
> decision, not a claim that Claude
> Code replaces every capability. No ongoing feature work or support is promised.

Three small, independently usable command-line guards for files touched by agents and automation:

- `shrink-guard.sh` owns a replacement and rejects unexpectedly small or empty content before it reaches the target.
- `nul-lint.sh` finds literal NUL bytes in Git text files, including staged blobs and explicitly selected untracked paths.
- `untrusted-intake.sh` inventories agent instruction, hook, and configuration surfaces in an unfamiliar checkout using static reads only.

These tools are intentionally narrow. In particular, `untrusted-intake.sh` is a triage aid, not a security review or malware certification.

## Requirements

- Bash 3.2 or newer
- Git and Perl for `nul-lint.sh`
- Perl core `Encode` and `JSON::PP` modules for `--json` in either scanner
- POSIX userland commands used by the scripts (`cksum`, `find`, `grep`, `mktemp`, `wc`)
- Python 3 only for JSON assertions in the test suite

No package manager or project-specific runtime is required.

## Install

Clone the repository, then either invoke commands from `bin/` or copy the three scripts to a directory on `PATH`:

```sh
install -d "$HOME/.local/bin"
install -m 0755 bin/shrink-guard.sh "$HOME/.local/bin/shrink-guard"
install -m 0755 bin/nul-lint.sh "$HOME/.local/bin/nul-lint"
install -m 0755 bin/untrusted-intake.sh "$HOME/.local/bin/untrusted-intake"
```

Alternatively, run `make install PREFIX="$HOME/.local"`. `DESTDIR` supports staged packaging.

Each script resolves no files relative to this repository, so it remains usable after being copied alone.

## Quick use

Guard any file rewrite. The default retained-size floor is 70 percent:

```sh
generate-report | shrink-guard ./docs/report.md
shrink-guard --check --from ./candidate.md ./docs/report.md
shrink-guard --force --audit-log ./rewrite-audit.tsv --from ./candidate.md ./docs/report.md
```

Scan tracked files, what is staged for the next commit, or selected untracked input:

```sh
nul-lint
nul-lint --staged
nul-lint --untracked-dir generated --extensions 'md,txt,json,yaml'
nul-lint --path 'incoming notes' --all-extensions
```

Statically inventory an unfamiliar checkout before opening its agent configuration in an agent-enabled tool:

```sh
untrusted-intake ../downloaded-project
untrusted-intake --json ../downloaded-project
```

All commands use the same exit-code family:

| Code | Meaning |
| ---: | --- |
| `0` | Accepted or clean |
| `1` | Operational failure, such as an unavailable dependency or unreadable path |
| `2` | Invalid command-line use or invalid input selection |
| `3` | Policy rejection or findings |

Detailed semantics and limits are indexed in [docs/README.md](docs/README.md). Runnable integration snippets live in `examples/`.

## Test

```sh
make test
```

The tests create only synthetic fixtures under the system temporary directory. They do not read user-level agent configuration or a global registry.

## Current verification

The 111 synthetic assertions cover successful scans, producer/read failures, interrupted checks, symlink ancestors, JSON control characters, Unicode, and independent installation. They pass on macOS 26.2 arm64 with both the system Bash 3.2.57 and Homebrew Bash 5.3.9. This README does not claim results on platforms that have not been tested for the current revision.

## License and maintenance

Copyright 2026 Aditya Dalmia. Licensed under [Apache-2.0](LICENSE), with
[attribution](NOTICE) and [source provenance](PROVENANCE.md). This is a public
reference implementation, deprecated for new Claude Code integrations as of 2026-09-22. See the [release preparation index](docs/release/README.md),
[contributing guide](CONTRIBUTING.md), and [security contact](SECURITY.md).
