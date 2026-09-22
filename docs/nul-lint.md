# `nul-lint.sh`

Git treats many NUL-containing files as binary, which can hide the useful line-level diff. `nul-lint.sh` reads bytes directly and reports the first NUL offset in each selected text file.

The default invocation scans tracked files in the working tree. `--staged` reads added, copied, modified, and renamed blobs from the Git index, even when the worktree copy differs. Untracked files are opt-in:

```sh
nul-lint.sh --untracked
nul-lint.sh --untracked-dir generated --untracked-dir imports
nul-lint.sh --path 'a selected file.md'
```

`--untracked` and `--untracked-dir` honor standard Git ignore rules. `--path` is a direct selection and includes ignored regular files. Explicit directories are traversed without following symlinks. Paths outside the current worktree are refused. Worktree scans skip symlink files and paths with symlink ancestors, while explicit selectors traversing a symlink are refused. Staged mode reads Git blob bytes and does not dereference worktree paths.

The built-in extension list covers common source, configuration, markup, and plain-text formats. Replace it with `--extensions 'md,txt,custom'` or `NUL_LINT_EXTENSIONS`. Use `--all-extensions` only when the selected scope is known to contain text; real binary formats routinely contain NUL bytes.

Path enumeration uses NUL delimiters so spaces are preserved. The JSON encoder preserves valid Unicode and escapes all JSON control characters, including backspace and ESC. It uses Perl core `Encode` and `JSON::PP`. Invalid UTF-8 in a reported filename fails with exit 1 before any JSON is emitted; it is not silently replaced. Human-readable output for unusual control characters may span lines.

`--staged` cannot be combined with worktree or untracked selectors. This keeps the answer tied to exactly what a commit would carry.

Git and explicit-directory enumeration must complete successfully before its manifest is scanned. A corrupt index, failed Git command, failed traversal, or unreadable selected regular file returns exit 1, never a clean result. Temporary NUL-delimited manifests are removed on ordinary exit and handled HUP/INT/TERM signals. Run against a stable checkout; enumeration and content reads are not an atomic filesystem snapshot.
