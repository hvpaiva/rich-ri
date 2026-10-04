# Changelog

User-visible changes are recorded here. This project follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Optional user YAML configuration with RI, environment and command-line
  precedence, effective-settings inspection and safe recovery from invalid files.
- Terminal, dark and light themes, per-role style overrides, configurable color
  depth and independent bat themes for shell commands and other languages.
- Theme and style completion, an annotated configuration example and a full
  configuration reference covering behavior, environment variables and trust.
- A terminal reader for installed Ruby and gem documentation, with semantic
  colors, Ruby syntax highlighting, Unicode-aware wrapping and plain output.
- Conservative recognition of shell transcripts with optional bat highlighting.
- Interactive discovery and dynamic completion for Bash, Zsh and Fish.
- A bundled manual, explicit dependencies and a tested gem installation path.
- Manual installation and terminal-width-aware formatting, with colors that
  respect the user's pager settings.

### Fixed

- Preserve heading level markers and ASCII horizontal separators in colored and
  plain output so readers can search for document sections in their pager.
- Ruby highlighting recognizes predicate, bang, setter and operator methods,
  including definitions and calls without parentheses. Symbols retain their
  style, and modulo operators are distinct from percent literals.

- Shell completion uses documentation sources configured in `RI`.
- Interactive Tab completion includes its required Readline adapter.
- Raw Markdown content cannot send terminal controls through rich rendering.
- Invalid dump paths and a missing manual viewer produce actionable errors.
- Contributor checks handle shallow pull request merge histories.

[Unreleased]: https://github.com/hvpaiva/rich-ri/commits/main
