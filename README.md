# Legacy Kandelo Homebrew Tap (Retired)

This repository is a retired snapshot of Kandelo's original Homebrew tap. The
public first-party tap and all active bottle publication now live in
[`Kandelo-dev/homebrew-tap-core`](https://github.com/Kandelo-dev/homebrew-tap-core).
Files here remain available only as migration history; they are not an active
package source or publication authority.

The technical notes below describe the legacy implementation at retirement.
They are retained for historical review and are not current operator
instructions.

## Formulae

Formulae under `Formula/` use normal Homebrew metadata and build their staged
upstream source through Kandelo's worktree-local SDK. Shared cross-compilation
and runtime-test mechanics live in
`Kandelo/formula_support/kandelo_formula_support.rb`.

Retained migration controls and pilots include:

- `hello`, the original publication control;
- `zlib` and `ruby`, the first dependency and heavy-runtime Formulae;
- `sqlite`, including the library and real command-line shell, plus the `bzip2`/`xz`
  compression tools and static libraries from the dependency-first source-build pilot;
- `zstd`, the threaded Zstandard library and command-line dependency root;
- `libmagic`, the full file-type database and compression-aware identification library;
- `openssl`, the first dependency-root library migration;
- `libpng` and `libxml2`, zlib-backed dependency-root libraries;
- `libzip`, the zlib-backed ZIP library and upstream archive comparison, merge, and inspection tools;
- `libcxx`, the LLVM C++ standard library, ABI runtime, and bundled unwinder;
- `icu`, the ICU 74.2 Unicode and globalization libraries with the complete
  common data archive;
- `musl-fts`, the BSD hierarchy traversal library for portable archive and filesystem tools;
- `libcurl`, the TLS, compression, threaded-resolver, and Unix-socket transfer library;
- `curl`, the matching command-line transfer client linked against the tap library;
- `ncurses`, the wide-character terminal library and CLI dependency root;
- `less` and its upstream `more` compatibility mode, terminal pagers linked against the tap's real ncurses termcap interface;
- `bash`, the GNU interactive shell with real pipelines, subprocesses, and process substitution;
- `sed`, the GNU stream-editing CLI used by shell and build workflows;
- `gzip`, the GNU compression CLI with native gunzip and zcat aliases;
- `grep`, GNU regular-expression and file search for the leaf CLI wave;
- `pcre2`, the Unicode-capable regex library, POSIX wrapper, and upstream CLI tools;
- `dash`, the dependency-free POSIX shell with instrumented subprocess support;
- `make`, GNU dependency-driven build automation using the tap's POSIX shell;
- `ed`, the conforming line editor and restricted editor required by patch workflows;
- `patch`, GNU's real multi-format file transformation utility replacing the compact metadata scanner;
- `asa`, FreeBSD's POSIX carriage-control translator for FORTRAN output;
- `m4`, the GNU macro processor with process-executing builtins backed by the tap's Dash shell;
- `gawk`, GNU's pattern scanning and text-processing language;
- `binutils`, GNU's native WebAssembly archive, symbol, and inspection suite,
  with exact trailing/representable `.wasm.*` custom-section and strip transforms,
  plus explicit rejection of relocatable, dynamic, cross-format, or lossy rewrites;
- `file`, compression-aware file type identification backed by the complete
  `libmagic` database;
- `fuser`, psmisc's process and open-file ownership inspector backed by
  Kandelo's live procfs process state;
- `what`, FreeBSD's SCCS identification-string extractor;
- `zip` and `unzip`, the security-patched Info-ZIP creation, extraction, and inspection tools.
- `libiconv`, GNU's complete character-set conversion library and CLI,
  replacing the compact base-image byte-copy fallback;
- `ncompress`, the upstream LZW `compress` and `uncompress` tools replacing the
  compact base-image fallback; GNU `gzip` owns the shared `zcat` command and
  reads both gzip and legacy compress streams.
- `pax`, the MirBSD pax, cpio, and tar interfaces for portable archive interchange.
- `gencat`, the POSIX message-catalog compiler producing catalogs consumed by
  Kandelo's musl `catopen` and `catgets` implementation.
- `procps`, the upstream `ps` process reporter backed by Kandelo's truthful
  cross-process procfs state.
- `ctags`, Universal Ctags' maintained tag generator, `readtags` query client,
  and optscript interpreter with complete C and C++ workflows.
- `tar`, the GNU archive creation and extraction CLI.
- `wget`, GNU HTTP and HTTPS retrieval linked against the tap TLS and compression roots.
- `coreutils`, the GNU filesystem, text, checksum, and shell utility suite.
- `diffutils`, GNU `diff`, `cmp`, `diff3`, and `sdiff` file-comparison tools.
- `findutils`, GNU filesystem traversal and argument-driven process execution.
- `vim`, the ncurses-backed editor, Ex mode, runtime, and `xxd` tools.
- `git`, distributed version control with Kandelo-native HTTP and HTTPS transport.

The SDK is not yet a Homebrew dependency. Trusted builds supply an
`HOMEBREW_KANDELO_ROOT` checkout containing the SDK, sysroot, kernel, and Node
host used by Formula `test do` blocks. Guest installation therefore requires a
published Kandelo bottle; building from source is currently a maintainer and CI
workflow.

During a source build, the shared Formula support removes Homebrew's global
`bin`/`sbin` directories and Kandelo runtime dependency executable directories
from the host `PATH`. Those paths can contain linked target Wasm from unrelated
Formulae as well as the current Formula's dependencies. Full tap names passed
to the `formula_opt_*` helpers resolve to the exact installed target keg, so a
native Homebrew alias with the same short name cannot redirect a cross build to
host headers or libraries. Formulae map those host keg paths to stable guest
opt paths for compiled runtime identities and explicit test staging. Native
Homebrew build dependencies remain available through their versioned `opt/bin`
paths.

SDK activation also exports `WASM_POSIX_DEP_PKG_CONFIG_PATH` from the existing
`lib/pkgconfig` and `share/pkgconfig` directories in the exact versioned kegs
of the Formula's declared Kandelo runtime dependency closure. The declaration
is rebuilt for each activation and replaces any ambient value; native,
undeclared, global, and mutable `opt` paths are never included. Formulae retain
ownership of `PKG_CONFIG_PATH`, which selects and orders the target `.pc`
directories the SDK may use.

Sysroot activation removes host `LIBRARY_PATH` before target compilation.
Otherwise pkgconf can classify a Kandelo dependency's library directory as a
native system path and remove its required `-L` flag. It also removes
`LD_RUN_PATH` so the native linker's implicit runtime search state cannot enter
the target build. The scoped Formula build helper restores the caller's
environment afterward.

Formula tests that fork process trees declare the exact descendant count. The
default contract requires every descendant to exit successfully; service tests
with intentional signal-based teardown may instead declare the exact multiset
of expected descendant statuses. Missing, extra, or unexpected descendants fail
the test.

Formula assertions that request merged output combine only the guest's stdout
and stderr callbacks in their original order. Host-runtime and worker
diagnostics remain on the embedding process's stderr and never become guest
assertion bytes.

The isolated Node runner used by `kandelo_run_wasm` receives `/bin/sh` from
Kandelo's reviewed binary resolver. The publisher materializes the wasm32 Dash
base-system artifact for every target architecture, including wasm64 Formula
builds, and a missing or stale artifact fails the test. An explicit `/bin/sh`
entry in `exec_programs:` remains authoritative for tests that deliberately
exercise another shell.

## Publication State

This repository cannot publish, dry-run, rebuild, roll back, or delete Kandelo
bottles. Its former `repository_dispatch` callers have been removed. The only
remaining Actions workflows are read-only checks that keep that retired state
fail-closed: they reject dispatch entry points, reusable-workflow jobs, package
permissions, secrets, and any unreviewed workflow-file additions.

Do not send bottle dispatches to this repository. Use the workflows and
operator documentation in `Kandelo-dev/homebrew-tap-core` instead. Existing
Formulae, sidecars, and package data are retained as historical evidence; this
retirement does not delete package data.
