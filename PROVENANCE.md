# Provenance

This repository is a standalone generalization of three scripts and their acceptance tests from a larger internal codebase.

Source revision: `494799eea3b9e7ce8686506a288c297ccf96be8d`

| Current file | Source file |
| --- | --- |
| `bin/shrink-guard.sh` | `bin/shrink-guard.sh` |
| `tests/shrink-guard-test.sh` | `bin/shrink-guard-test.sh` |
| `bin/nul-lint.sh` | `bin/nul-lint.sh` and `bin/lib/fmt.sh` |
| `tests/nul-lint-test.sh` | `bin/nul-lint-test.sh` |
| `bin/untrusted-intake.sh` | `bin/untrusted-intake.sh` |
| `tests/untrusted-intake-test.sh` | `bin/untrusted-intake-test.sh` |

Project-specific names, paths, issue identifiers, defaults, and fixtures were removed. The command interfaces, target selection, local audit behavior, static-scan scope, and portability contracts were rewritten for independent use.

No upstream remote name or private filesystem location is recorded here.
