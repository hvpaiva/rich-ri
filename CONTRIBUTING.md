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
programs and exits nonzero if the full check cannot run. Install groff, Bash,
Zsh, Fish and bash-completion 2.x through your system's package manager.

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

Pull request title, commit-range and changelog checks depend on the GitHub event
and run separately in CI. Run `ruby bin/lint-commits BASE..HEAD` locally to check
a commit range.

Other entry points are `rake format`, `rake generate`, `rake test:shells`,
`rake package:check`, `rake build` and `rake -T`. Generated man pages are committed;
run `rake generate` in the same change as any option or manual change.

Tests generate a temporary RI store from fixtures. They do not need system Ruby
documentation or a particular gem installed with documentation. Shell tests run
real Bash, Zsh and Fish processes. The Zsh test captures calls to `compadd`;
the Fish test exercises `complete -C`. Missing shells skip in the fast loop and
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
90% of lines and 80% of branches, including the CLI subprocesses. These floors
are a guard against lost coverage, not a substitute for reviewing test quality.

Write source, documentation, comments, commits and pull requests in English.
Human review checks clear prose, useful comments, focused responsibilities,
compatibility and accessibility. Non-English strings in tests are appropriate
when they exercise Unicode handling.

Use Conventional Commits, such as `fix: preserve blank lines in shell examples`.
Keep commits focused and passing, and omit attribution trailers. CI validates
commit subjects and pull request titles. User-visible code changes need a line
under `Unreleased` in `CHANGELOG.md`; maintainers may apply `skip-changelog` for
changes that have no user-visible effect.

Describe the problem, resulting behavior and validation in the pull request.
Update README, help and the manual where users will look for the changed feature.
The generated manual and completion descriptions share the option parser to
prevent drift. Tests check documented invocations and the distributed package.

## Maintenance and releases

Dependabot proposes gem and action updates. Review the diff and run the full
checks; a passing update is not automatically merged. Actions are pinned by SHA,
and the weekly dependency audit can detect advisories between code changes.

See [docs/releasing.md](docs/releasing.md) for preparation, repository settings,
trusted publishing and recovery. Release publication runs only in GitHub Actions,
after the complete CI workflow succeeds for the release commit.
