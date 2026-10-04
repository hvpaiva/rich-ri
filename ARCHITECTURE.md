# Architecture

rich-ri keeps RDoc responsible for documentation storage and lookup. It supplies
a terminal formatter, highlighting, page completion and shell adapters around
RDoc's RI driver. It does not index project source, execute examples or fetch
documentation.
RDoc is a required gem dependency. The `ri` executable is not invoked; `rich-ri`
loads the same reader library directly.

## Boundaries

- `Configuration` selects one user YAML file, validates its schema and resolves
  file and environment settings. No project file is loaded automatically.
  `Options` combines those settings with RI defaults and explicit arguments,
  and owns the descriptions used by help, completion and the generated manual.
  `CLI` selects utility actions or starts the RI driver.
- `Theme` validates semantic styles, resolves foreground presets and converts
  colors for the selected terminal depth. The formatter, Ruby highlighter and
  help share the same roles. bat uses separately configured themes.
- `Driver` extends RI lookup with page discovery and marks signatures and method
  lists so the formatter can style them. Explicit `--format` delegates to RDoc.
- `Formatter` visits the RDoc document tree. Prose wrapping uses Reline's terminal
  cell widths; balanced ANSI styles avoid leaking color into later paragraphs.
- `Highlighter` uses Prism's syntax tree to locate Ruby method calls, definitions
  and symbols, then colors the lexer tokens at their original byte offsets.
  Infix operators and indexing keep their own styles; they are also calls in
  Ruby's syntax tree. Tokens are sorted into source order for heredocs, with
  lexical fallback for incomplete examples and RI signatures.
  Ruby stays in process and uses the selected semantic theme without requiring bat.
  Other languages go to bat with an argument array and source through stdin.
- `Completion` exposes a tab-separated candidate/description protocol consumed
  by the three shell scripts. Only documentation-source arguments reach lookup;
  source options follow the same RI, configuration and command-line precedence
  as the reader. Completion cannot start a pager, server or cache dump.
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
Configuration is parsed as data with YAML aliases and object loading disabled;
unknown keys and invalid values fail before reading documentation. Style strings
cannot inject raw terminal controls. File-relative documentation paths resolve
from the selected file, while RI and command-line paths retain their usual
working-directory semantics. Pager command strings are trusted user settings
from configuration, the RI environment or explicit arguments.

Tests create their own RI store, use fixture documents for rendering, exercise
the real executable and install the built gem into a separate gem home. The
manual is generated from `Options`; the shell scripts remain small adapters.

## Configuration contract

The public [configuration reference](docs/configuration.md) defines the supported
keys, roles, flags and environment variables. Built-in defaults are overridden by
`RI`, the YAML file, dedicated environment variables, then command-line flags.
Style maps merge by role, and documentation directories accumulate. Each command
resolves its configuration once; a theme does not modify the terminal palette.
Printing help, version, completion scripts or the selected file path bypasses a
broken file so users can diagnose it. Documentation-name completion stays silent
on invalid configuration; option and theme suggestions remain available.
Completion never executes utility actions or pager commands.

The annotated YAML example and documentation tests cover the supported schema,
role names and environment variables. The manual is generated from the same
option descriptions as help and completion; generation checks prevent drift.
