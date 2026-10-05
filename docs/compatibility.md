# Compatibility

## Supported environments

| Component | Support |
| --- | --- |
| Ruby | MRI 3.4 and 4.0. The gem requires Ruby 3.4 or later. |
| Operating system | Linux and macOS. Other systems and Ruby engines are untested. |
| RDoc | 8.1 or later in the 8.x series. |
| RI stores | Current RDoc output, plus RDoc 6.14 stores on Ruby 3.4. Regenerate caches when moving between Ruby 3 and 4. |
| Completion | Bash with bash-completion 2.x, Zsh and Fish. |
| Terminal | Plain output works without ANSI support. Colors depend on the terminal palette and capabilities. |

CI runs Ruby 3.4 and 4.0 on Linux and Ruby 4.0 on macOS. A separate Ruby 3.4 job
tests the minimum runtime dependency set in [minimum.gemfile](../gemfiles/minimum.gemfile).
Another job resolves current dependencies. The locked bundle is used for normal
development and releases. Shell integrations run natively on both platforms;
CI also checks the [container test environment](development.md#shell-tests)
available to contributors.

## Changes between versions

The supported interface consists of the executable, documented options,
configuration keys, environment variables and shell completion installation.
The default heading markers remain available for pager searches. Page layout and
syntax colors may improve in patch releases. Page output is intended for
interactive reading and has no stable format for parsing by scripts.

While rich-ri is below 1.0, patch releases preserve that interface. Incompatible
changes require a minor release and migration instructions in the changelog.
From 1.0 onward, incompatible changes require a major release. Ruby classes and
the internal completion protocol are implementation details.

Dropped Ruby, RDoc or platform support follows the same versioning policy. An
upcoming removal is announced in the changelog at least one minor release ahead,
except where a security fix requires an earlier change.

Only the latest released version receives fixes. See the
[security policy](../SECURITY.md) for vulnerability reports and
[maintenance guide](maintenance.md) for urgent releases.
