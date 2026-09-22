# Validation

Verified 2026-09-22: **111 assertions passed on macOS and Linux**.
Breakdown: shrink guard35, NUL scanner35, intake scanner37, installation4.

- macOS: Bash3.2.57 with a restricted PATH that also selects system Bash for nested
  commands, and Homebrew Bash5.3.9. Tests explicitly cover standalone installed scripts.
- Linux: non-root Alpine container, Bash5.3.9, Perl5.42, Git2.54.0; network disabled.
- Command: `make test`. A BSD/GNU stat test-fixture difference was corrected during
  Linux verification; both tool behavior and assertions now pass there.

Review fixed false clean results after enumeration failures, symlink boundary
escapes, invalid JSON, signal handling, byte-measurement failures, and genuine
Bash3.2 empty-array handling. The stable-checkout and static-triage limits remain.

Runtime/test snapshot SHA-256: `13c90990475c81fb94a5dc6c7405a9682960261c73fa1e37acdfe46a6e546eaf`.
The digest covers sorted relative paths, file SHA-256 and executable bits for
runtime/tests plus Makefile. Documentation and generated files are excluded.

See the companion `flightdeck-examples` repository for the Linux harness.
