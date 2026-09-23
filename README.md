# Agent File Guards

Three small command-line guards for files that agents and automation touch: `shrink-guard` refuses
a rewrite that would unexpectedly shrink or empty a file, `nul-lint` finds NUL bytes in Git text
files, and `untrusted-intake` lists the agent instruction, hook, and configuration files in an
unfamiliar checkout before you open it with an agent-enabled tool.

> **Status:** public Apache-2.0 reference implementation, deprecated for new Claude Code
> integrations as of 2026-09-22. Not a claim that Claude Code replaces every capability; no
> ongoing feature work or support is promised.

## What it does

- `shrink-guard.sh` owns a replacement and rejects unexpectedly small or empty content before it reaches the target.
- `nul-lint.sh` finds literal NUL bytes in Git text files, including staged blobs and explicitly selected untracked paths.
- `untrusted-intake.sh` inventories agent instruction, hook, and configuration surfaces in an unfamiliar checkout using static reads only.

Each guard is one Bash script, usable on its own. All three share one exit-code family.

## Why it exists

- A generated replacement can silently lose most of a file. `shrink-guard` compares the complete
  candidate with the current file (default floor: 70 percent of its bytes) and rejects empty content.
- Git treats many NUL-containing files as binary, which can hide the useful line-level diff.
  `nul-lint` reads bytes directly and reports the first NUL offset in each selected text file.
- Instruction files, hooks, and agent configuration in a downloaded project may influence an agent.
  `untrusted-intake` inventories them without sourcing files, executing hooks, or running checkout
  commands, so you can review them first.

## Install

Requires Bash 3.2 or newer and the POSIX userland commands the scripts use (`cksum`, `find`,
`grep`, `mktemp`, `wc`). `nul-lint.sh` also needs Git and Perl; `--json` in either scanner needs the
Perl core `Encode` and `JSON::PP` modules. Python 3 is used only for JSON assertions in the test
suite. No package manager or project-specific runtime is required.

Clone the repository, then either invoke commands from `bin/` or install the three scripts to a
directory on `PATH`:

```sh
git clone https://github.com/AdityaVikramDalmia/flightdeck-agent-file-guards.git
cd flightdeck-agent-file-guards
make install PREFIX="$HOME/.local"
export PATH="$HOME/.local/bin:$PATH"
```

`DESTDIR` supports staged packaging. The same installation by hand:

```sh
install -d "$HOME/.local/bin"
install -m 0755 bin/shrink-guard.sh "$HOME/.local/bin/shrink-guard"
install -m 0755 bin/nul-lint.sh "$HOME/.local/bin/nul-lint"
install -m 0755 bin/untrusted-intake.sh "$HOME/.local/bin/untrusted-intake"
```

Each script resolves no files relative to this repository, so it remains usable after being copied alone.

## Quick use

Statically inventory an unfamiliar checkout before opening its agent configuration in an agent-enabled tool:

```sh
untrusted-intake ../downloaded-project
untrusted-intake --json ../downloaded-project
```

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

All commands use the same exit-code family:

| Code | Meaning |
| ---: | --- |
| `0` | Accepted or clean |
| `1` | Operational failure, such as an unavailable dependency or unreadable path |
| `2` | Invalid command-line use or invalid input selection |
| `3` | Policy rejection or findings |

Detailed semantics and limits are indexed in [docs/README.md](docs/README.md). Runnable integration snippets live in `examples/`.

## Limits

- These tools are intentionally narrow. In particular, `untrusted-intake.sh` is a triage aid, not a
  security review or malware certification. An indicator match is not proof of prompt injection,
  and absence of a match is not proof of safety; general source code and dependencies are not
  inspected ([details](docs/untrusted-intake.md)).
- `shrink-guard` measures bytes: it catches large content loss, not a same-size semantic rewrite.
  It protects only writes it performs itself, has no inter-process lock, and does not call `fsync`
  ([details](docs/shrink-guard.md)).
- The scanners expect a stable checkout; their reads are not an atomic filesystem snapshot
  ([nul-lint](docs/nul-lint.md), [untrusted-intake](docs/untrusted-intake.md)).

## Test

```sh
make test
```

The tests create only synthetic fixtures under the system temporary directory. They do not read user-level agent configuration or a global registry.

The 111 synthetic assertions cover successful scans, producer/read failures, interrupted checks, symlink ancestors, JSON control characters, Unicode, and independent installation. They pass on macOS 26.2 arm64 with both the system Bash 3.2.57 and Homebrew Bash 5.3.9. This README does not claim results on platforms that have not been tested for the current revision.

## License and maintenance

Copyright 2026 Aditya Dalmia. Licensed under [Apache-2.0](LICENSE), with
[attribution](NOTICE) and [source provenance](PROVENANCE.md). This is a public
reference implementation, deprecated for new Claude Code integrations as of 2026-09-22. See the [release preparation index](docs/release/README.md),
[contributing guide](CONTRIBUTING.md), and [security contact](SECURITY.md).
