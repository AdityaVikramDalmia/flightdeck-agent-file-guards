# `untrusted-intake.sh`

`untrusted-intake.sh` performs a static inventory of known agent-control surfaces in a checkout. It reads regular carrier files with `find`, `wc`, and `grep`; JSON serialization additionally requires Perl core `Encode` and `JSON::PP`; it does not source files, execute hooks, invoke package managers, or run checkout commands.

The inventory includes instruction files named `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, and `SKILL.md`; common root configuration files; and files below common agent configuration directories. Git hooks are excluded by default because a normal `.git/hooks` directory contains samples. Add `--include-git-hooks` to inventory non-sample hook files.

Every carrier is a finding because its content may influence an agent. A second `INDICATOR` row marks a narrow set of phrases and configuration keys that deserve manual attention. A match is not proof of prompt injection, and absence of a match is not proof of safety.

Symlink carriers are reported without following their content. Every component of a configured surface is checked: for example, a symlink at `.cursor` blocks inspection of `.cursor/rules`, and a symlink at `.git` blocks the optional hooks scan. Broken configuration symlinks are findings too. A carrier over `--max-bytes` is reported as `UNSCANNED` rather than read for indicators. Traversal prunes top-level `.git` (apart from explicitly requested hooks), `node_modules`, and `vendor`.

This tool does not inspect general source code, dependencies, compiled files, hidden behavior, or every configuration format. It is not a sandbox, security assessment, or malware certification. Review findings as untrusted data in a viewer that will not automatically apply the instructions.

Traversal, carrier metadata, and content-read failures return exit 1. A partial or failed `find` result cannot become a clean scan. JSON strings preserve valid Unicode and escape control bytes such as backspace and ESC. Invalid UTF-8 in a reported path or indicator returns exit 1 before JSON output begins. Indicator previews replace embedded NUL bytes with `?` because Bash variables cannot contain NUL.

Run against a stable checkout with no concurrent writer. These shell checks do not provide an atomic no-follow filesystem API: an adversarial process can change a path between the symlink check and the read. For actively changing hostile content, isolate a snapshot first. Use trusted binaries and environment settings; the scanner does not sandbox `PATH` or interpreter configuration.
