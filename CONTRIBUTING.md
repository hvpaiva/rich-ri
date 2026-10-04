# Contributing

Bug reports, documentation improvements and focused pull requests are welcome.
Please follow the [code of conduct](CODE_OF_CONDUCT.md).

## Set up

Development uses Ruby 4.0.7. `mise.toml` pins Ruby and the external lint tools.
Ruby 3.4 is the minimum runtime; Ruby 3.4 and 4.0 are tested in CI.

```sh
mise install
bin/setup
bundle exec rake
```

mise is optional if the pinned tools are already installed. `bin/setup` installs
the bundle and, when mise is available, the lint tools. It reports missing system
programs and exits nonzero if the full check cannot run. Install groff, man, Bash,
Zsh, Fish and bash-completion 2.x through your system's package manager. These are
development requirements for testing every supported integration, not runtime
requirements for reading documentation.

Run the local executable with `bundle exec ruby -Ilib exe/rich-ri --help`.

## Checks

`bundle exec rake` runs Ruby lint and tests. Before submitting a pull request, run:

```sh
bundle exec rake check
```

This runs the local counterparts of CI checks: lint, spelling, workflow security,
local documentation links, manual rendering/freshness, tests with coverage, all
three shells, a gem installation smoke test and a dependency audit. The audit
updates its database and needs network access. `rake audit:local` is useful
offline but cannot confirm that the advisory database is current.

Commit checks compare the current branch with `origin/main`, falling back to
`HEAD` when that reference is absent. To select another range, run
`bundle exec rake 'lint:commits[BASE..HEAD]'`. CI also validates the pull request
title, body and changelog using its event context. `PR_TITLE` and `PR_BODY` let
you supply those texts to the local commit check.

Other entry points are `rake format`, `rake generate`, `rake test:shells`,
`rake package:check`, `rake build` and `rake -T`. Generated man pages are committed;
run `rake generate` in the same change as any option or manual change.

Tests generate a temporary RI store from fixtures. They do not need system Ruby
documentation or a particular gem installed with documentation. Shell tests run
real Bash, Zsh and Fish processes, including completion insertion through a
terminal and Fish's `complete -C`. Missing shells skip in the fast loop and
fail in `test:shells` and CI. Real bat behavior is checked when bat is installed;
its missing, failing and content-changing cases are covered using test programs.

CI also tests macOS, the oldest supported Ruby and a fresh dependency resolution.
The lockfile gives contributors a reproducible environment; consumers resolve
the runtime dependencies declared in the gemspec.

## Changes and review

Add a regression test for a bug and integration coverage for new CLI behavior.
Keep rendered output and completion useful without color, without bat and in
pipes. Tests should prove behavior rather than duplicate the implementation.

RuboCop enforces formatting and configured code conventions. Exceptions belong
in `.rubocop.yml` with a reason; inline disabling is rejected. Coverage enforces
90% of lines and 80% of branches in `lib`, including CLI subprocesses. These
numbers describe the runtime library; maintenance scripts and shell adapters
have separate behavior tests. The floors guard against lost coverage and do not
replace review of test quality.

Write source, documentation, comments, commits and pull requests in English.
Human review checks clear prose, useful comments, focused responsibilities,
compatibility and accessibility. Non-English strings in tests are appropriate
when they exercise Unicode handling.

Use Conventional Commits, such as `fix: preserve blank lines in shell examples`.
Keep commits focused and passing, and omit generated attribution trailers. CI validates
commit subjects, pull request titles and generated attribution in commit/PR
text; legitimate human coauthors are welcome. User-visible code changes need a line
under `Unreleased` in `CHANGELOG.md`; maintainers may apply `skip-changelog` for
changes that have no user-visible effect.

Describe the problem, resulting behavior and validation in the pull request.
Update README, help and the manual where users will look for the changed feature.
When page rendering changes, [refresh the README comparison](docs/images/README.md)
against `ri -f ansi` and inspect the resulting image.
The generated manual and completion descriptions share the option parser to
prevent drift. A test runs the README's project example as written and compares
its output. Package checks install the built gem in isolation and exercise it.

## Maintenance and releases

Dependabot proposes gem and action updates. Review the diff and run the full
checks; a passing update is not automatically merged. Actions are pinned by SHA,
and the weekly dependency audit can detect advisories between code changes.

The repository requires pull requests, signed commits and passing checks on
`main`. Merge commits preserve contributors' signed commits; squash and rebase
merges are disabled. A second maintainer's approval is not required.

Maintainers can inspect the repository's security and release settings with
`bundle exec rake github:verify`, or apply the project's settings with
`bundle exec rake github:setup`. Both commands use the authenticated `gh`
account; setup requires repository administration access.

From a clean, up-to-date `main`, with `gh` authenticated and Git signing configured:

```sh
bin/release X.Y.Z --push
```

The command prepares the version, changelog and manual, runs the full checks,
opens a release pull request with a signed commit, waits for CI, merges, signs
and pushes the tag, and watches publication. Without `--push` it stops at the pull request;
`--dry-run` validates and previews the changelog without writing or pushing.

The tag workflow reruns CI and publishes through RubyGems trusted publishing.
The publisher uses repository `hvpaiva/rich-ri`, workflow `release.yml` and
environment `release`. `rake release` is the CI publish step and refuses to run
locally. Configure the publisher before the first release.

The command checks the repository settings before changing files and recognizes
an existing release branch, pull request or tag when resuming. Follow its next
action after a failure. Published tags stay immutable; a retry must not replace
a tag or publish an accepted gem again.
