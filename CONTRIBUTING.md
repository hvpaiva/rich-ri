# Contributing

Bug reports, documentation fixes and code contributions are welcome. For a new
feature or a substantial design change, open an issue to discuss it first.
Please follow the [code of conduct](CODE_OF_CONDUCT.md).

## Set up

Fork the repository on GitHub and clone your fork. From the checkout:

```sh
git remote add upstream https://github.com/hvpaiva/rich-ri.git
git switch -c fix/short-description
mise install
bin/setup
bundle exec rake
```

`mise.toml` pins Ruby and the lint tools. If you manage them another way, install
the listed versions and skip `mise install`. `bin/setup` installs the bundle and
reports missing system programs. The full checks need groff and man, plus either
Bash, Zsh, Fish and bash-completion 2.x or a running Docker/Podman engine for
[isolated shell tests](docs/development.md#shell-tests). Install system programs
through your package manager.

Run the checkout with:

```sh
bundle exec ruby -Ilib exe/rich-ri String#scan
```

## Make a change

Start with a failing regression test for a bug. Exercise new command behavior
through the real executable, and keep lookup and completion useful with colors
or optional programs disabled. Tests should check observable behavior.

The runtime is under `lib/rich_ri`; [ARCHITECTURE.md](ARCHITECTURE.md) describes
its boundaries. Tests create temporary RI stores and do not depend on your
installed documentation. [Ruby documentation samples](test/fixtures/corpus/README.md)
cover examples from upstream. Maintenance code lives in `rakelib` and `bin`.

Write code, documentation and commits in English. Use concise comments to explain
intent where the code needs context. Unicode text is welcome in tests that
exercise rendering. RuboCop enforces code conventions; justified exceptions belong
in `.rubocop.yml`, with a reason. Inline disables are rejected.

Update the user-facing documentation with the behavior you change:

- README for installation and everyday use.
- [Usage](docs/usage.md), [completion](docs/shell-completion.md) or
  [configuration](docs/configuration.md) for detailed behavior.
- Help and the manual for options and environment variables. Run
  `bundle exec rake generate` after changing their sources.
- `CHANGELOG.md` under `Unreleased` for changes visible to users.

When rendering changes, [regenerate the comparison](docs/images/README.md) and
inspect the image. Review prose as a new reader: introduce the result before the
mechanics, keep examples runnable and place details in the relevant guide.

## Check your work

For documentation-only changes:

```sh
bundle exec rake docs:check
```

This checks local links, spelling, the generated manual and runnable examples.
See [documentation checks](docs/development.md#documentation-checks) for which
files qualify for the shorter CI run.

For code, dependencies, scripts or workflow changes:

```sh
bundle exec rake check
```

This runs Ruby and shell lint, spelling, workflow security, local links, manual
checks, tests with coverage, all three shells, installation of the built gem and
a dependency audit. The audit updates its database over the network.
`bundle exec rake audit:local` uses the last downloaded database.

For a shorter loop, `bundle exec rake` runs Ruby lint and tests, skipping shell
integrations unavailable locally. The full `check` task requires all three shells
to pass, using a container when needed. To run one file:

```sh
bundle exec ruby -Ilib -Itest test/highlighter_test.rb
```

The full CI suite also tests Linux and macOS, supported Ruby versions, current and minimum
dependencies, and an older RI store. See [compatibility checks](docs/development.md#compatibility-checks)
for the local commands, and [performance measurements](docs/development.md#performance)
to compare startup, rendering and completion.

Coverage must stay above 90% of runtime lines and 80% of branches. Check the
behavior of changed code even when the totals pass. Maintenance scripts and
shell adapters have their own behavior tests. Human review covers clarity,
accessibility, design and compatibility.

## Open a pull request

Sign your commits with an SSH or GPG signing key registered on GitHub.
[GitHub's signing guide](https://docs.github.com/en/authentication/managing-commit-signature-verification/signing-commits)
explains the setup. Use Conventional Commits, for example:

```sh
git add lib test
git commit -S -m "fix: preserve shell output after highlighting"
```

Keep commits focused and passing. Describe the problem, resulting behavior and
validation in the PR. The commit check validates commit subjects and the PR title
and body. Maintainers may use `skip-changelog` for changes without a user-visible
effect.

Push to your fork and open a PR against `main`, or against the agreed hotfix branch.
PRs require signed commits, passing checks and resolved review threads. Merge
commits preserve contributors' signatures. Address feedback with focused commits;
coordinate before rewriting a branch someone else is using.

## Project decisions

[Highlander Paiva](https://github.com/hvpaiva) maintains rich-ri, reviews changes
and manages releases. Design discussions belong in issues or pull requests so
contributors can follow the decisions. Reports are triaged by impact and whether
there is a reproducible example; security reports use the
[private channel](SECURITY.md).

Regular contributors may ask to help with triage, review or releases. New
maintainers start with the access needed for their responsibilities. A transfer
of ownership should name the successor publicly and cover both the GitHub
repository and RubyGems ownership. [Maintenance](docs/maintenance.md) describes
the release process and recovery steps.
