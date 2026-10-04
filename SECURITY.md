# Security

## Report a vulnerability

Use [private vulnerability reporting](https://github.com/hvpaiva/rich-ri/security/advisories/new)
or email [contact@hvpaiva.dev](mailto:contact@hvpaiva.dev) with affected versions,
reproduction steps and impact. Please do not put exploit details or secrets in
a public issue. The maintainer will coordinate a fix and disclosure with you;
response time depends on availability.

Security fixes target the latest released version. There is no promise to
backport fixes to older 0.x releases. Ordinary bugs belong in GitHub issues.

## Trust boundaries

rich-ri reads the active Ruby's documentation and explicitly selected RI stores.
RDoc uses Ruby Marshal caches, which can instantiate Ruby objects while loading.
Do not point `--doc-dir` or `--dump` at untrusted files, or install untrusted
documentation into a searched directory. Completion reads the same trusted stores.

Ruby examples are parsed, never evaluated. Shell examples are tokenized, never
executed. Optional bat receives source on stdin with separate command arguments.
Its configuration file is disabled, and output that alters source is discarded.
Terminal controls in rich rendering are escaped; original RDoc formatters retain
upstream behavior when explicitly selected with `--format`.

Configuration files use safe YAML parsing: aliases, object tags, unknown keys and
invalid values are rejected. There is no Ruby evaluation, shell interpolation or
automatic project configuration search. Style strings use a restricted grammar;
raw terminal escapes are not accepted. A custom file selected with `--config` or
`RICH_RI_CONFIG` is still trusted input: it may select RI stores and a pager command.

`pager` command strings, `--pager-command`, `RI_PAGER` and `PAGER` are trusted
command settings interpreted by RDoc. `PATH` selects bat and other external
programs. Do not accept these settings from untrusted input. `--show-config` may
include command arguments and paths from your environment; review it before
sharing its output. `--server` deliberately enables RDoc's HTTP server; consult
RDoc before exposing it on a network.

## Supply chain

The gem declares runtime dependencies and its supported Ruby range. Development
uses a committed lockfile, automated dependency updates and a vulnerability audit.
GitHub Actions use pinned commits and minimal job permissions. Releases verify
the tag, version, changelog and main-branch ancestry, then use RubyGems trusted
publishing. Publication credentials are short-lived and scoped to this gem.

Changes to protected branches go through pull requests with signed commits and
passing checks. Release tags and the publication environment are restricted,
and published GitHub releases are immutable. Maintainers verify these settings
before release. RubyGems trust must be configured for the repository, workflow
and environment described in [Maintenance and releases](CONTRIBUTING.md#maintenance-and-releases).
