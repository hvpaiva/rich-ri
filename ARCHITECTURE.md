# Architecture

rich-ri keeps RDoc responsible for documentation storage and lookup. It supplies
a terminal formatter, highlighting and completion discovery around RDoc's RI
driver. It does not index project source, execute examples or fetch documentation.
RDoc is a required gem dependency. The `ri` executable is not invoked; `rich-ri`
loads the same reader library directly.

## Boundaries

- `Options` owns parsing and the descriptions used by help, completion and the
  generated manual. `CLI` selects utility actions or starts the RI driver.
- `Driver` extends RI lookup with page discovery and marks signatures and method
  lists so the formatter can style them. Explicit `--format` delegates to RDoc.
- `Formatter` visits the RDoc document tree. Prose wrapping uses Reline's terminal
  cell widths; balanced ANSI styles avoid leaking color into later paragraphs.
- `Highlighter` uses Prism's syntax tree to locate Ruby method calls, definitions
  and symbols, then colors the lexer tokens at their original byte offsets.
  Infix operators and indexing keep their own styles; they are also calls in
  Ruby's syntax tree. Tokens are sorted into source order for heredocs, with
  lexical fallback for incomplete examples and RI signatures.
  Ruby stays in process and uses the terminal palette without requiring bat.
  Other languages go to bat with an argument array and source through stdin.
- `Completion` exposes a tab-separated candidate/description protocol consumed
  by the three shell scripts. Only documentation-source arguments reach lookup;
  source options from `RI` apply before explicit arguments. Completion cannot
  start a pager, server or cache dump.
- `Manual` opens the bundled page and installs an explicit copy on request.
  Its pager palette preserves existing user configuration.

The runtime files under `lib/` form one small library. The supported public
interface is the executable, its flags and the installed completion scripts;
Ruby classes and the internal `--complete` protocol can change before 1.0.

## Shell transcripts

An untagged block can be a shell transcript only if its first nonblank line is a
plausible `$ command` prompt. Executable names, paths and environment assignments
are recognized without a command allowlist. Later prompts must have the same
indentation. Explicit backslash continuations may consume secondary `> ` prompts.
Only commands are highlighted; output is preserved. Ambiguous prompts and shell
heredocs are left plain, and explicit Ruby/text tags override detection.

bat is optional. Its output is accepted only when removing SGR color codes yields
the input exactly. Failed processes, missing executables and altered content
fall back to the original text. Repeated examples are cached per formatter.

## Compatibility and trust

The driver and formatter extend RDoc APIs, including visitor methods that may
change between releases. RDoc 8.1 is the baseline and the gem restricts updates
to the 8.x series. CI tests the locked version and a fresh resolution; dependency
updates must exercise rendering, lookup, completion and installed-package tests.

RI cache files use Marshal and must be trusted, including when used only for
completion. Terminal controls in rich rendering are shown as escaped text.
Selecting an original RDoc formatter delegates its output behavior to RDoc.
Pager commands are deliberately inherited from the user's RI environment.

Tests create their own RI store, use fixture documents for rendering, exercise
the real executable and install the built gem into a separate gem home. The
manual is generated from `Options`; the shell scripts remain small adapters.
