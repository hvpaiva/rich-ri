# Changelog

User-visible changes are recorded here. This project follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Shell integration tests can run in Docker or Podman when local shells are
  unavailable, with the same required checks used in CI.
- Compatibility checks for minimum runtime dependencies and older RI stores,
  upstream Ruby documentation samples and repeatable CLI performance measurements.
- Release artifact checksums, build attestations and a protected hotfix workflow.
- Focused guides for reading, configuration, completion, troubleshooting,
  compatibility, contribution and maintenance.
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

- Long options require their full names so configuration selection and completion
  cannot silently interpret abbreviations differently.
- Missing optional gems for `--server` and `--profile` explain how to install them;
  help and the manual describe these dependencies.
- Required shell tests fail when Fish or Zsh is unavailable; test environment
  cleanup preserves the suite's shell requirement flag.
- Optional bat highlighting has time and size limits, handles invalid encoding
  and falls back to the original text without blocking subsequent examples.
- Incompatible RI cache formats explain how to regenerate documentation.
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
