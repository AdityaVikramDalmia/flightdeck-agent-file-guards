# `shrink-guard.sh`

`shrink-guard.sh` buffers a complete candidate, compares it with the current regular file, stages the candidate in the target directory, and replaces the target with a rename. Readers therefore see either the old file or the fully written new file when the target directory and rename implementation provide normal local-filesystem atomicity.

The default rule rejects a candidate below 70 percent of the old file's byte count. `--min-percent` accepts values from 0 through 100. Byte count catches large content loss without depending on line wrapping; it does not detect a same-size semantic rewrite.

Empty or whitespace-only content is rejected for both existing and new files. `--force` alone overrides only the size threshold. Installing empty content requires the two explicit flags `--force --allow-empty`.

Rejected write-mode candidates are saved as `TARGET.rejected-TIMESTAMP-PID`. Use `--discard-rejected` when retaining that data would be undesirable. Check mode writes neither target, reject copy, nor audit log.

Rejects and overrides are audited to `TARGET.shrink-guard.audit.tsv` by default. `--audit-log` selects another local path. `--no-audit` disables logging explicitly. An override that requires an audit is refused if its audit record cannot be appended; with `--no-audit`, the caller has explicitly waived that record.

Existing file permissions and timestamps are copied to the staging inode before its content is replaced. New targets receive the secure mode chosen by `mktemp`, normally `0600`.

## Concurrency and filesystem limits

The script compares a checksum immediately before rename and refuses if another writer changed the target. This narrows the time-of-check/time-of-use race but does not eliminate it: there is still a small window between the final checksum and rename, and there is no inter-process lock. Cooperating writers should add their own lock.

Atomic replacement applies to the file name, not to durability after power loss. The tool does not call `fsync`. Network filesystems may provide weaker rename behavior. Symlink targets are refused because replacing a symlink and replacing its referent have different semantics.

The command must own the write to provide its guarantee. Checking a candidate and then writing the target through a different command is not protected.

All byte measurements and checksums are checked for failure; a failed measurement is an operational error, not an empty value eligible for acceptance. HUP, INT, and TERM exit with 129, 130, and 143 respectively when Bash can handle the signal, and the EXIT handler removes candidate/staging files. A signal received during a child command may be handled only when that child returns. SIGKILL cannot run cleanup, and a signal arriving after a completed rename cannot roll the rename back.
