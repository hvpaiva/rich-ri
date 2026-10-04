# Changelog

User-visible changes are recorded here. This project follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- A terminal reader for installed Ruby and gem documentation, with semantic
  colors, Ruby syntax highlighting, Unicode-aware wrapping and plain output.
- Conservative recognition of shell transcripts with optional bat highlighting.
- Interactive discovery and dynamic completion for Bash, Zsh and Fish.
- A bundled manual, explicit dependencies and a tested gem installation path.
- Manual installation and terminal-width-aware formatting, with colors that
  respect the user's pager settings.

### Fixed

- Shell completion uses documentation sources configured in `RI`.
- Interactive Tab completion includes its required Readline adapter.
- Raw Markdown content cannot send terminal controls through rich rendering.
- Invalid dump paths and a missing manual viewer produce actionable errors.
- Contributor checks handle shallow pull request merge histories.

[Unreleased]: https://github.com/hvpaiva/rich-ri/commits/main
