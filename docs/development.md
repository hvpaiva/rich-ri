# Development checks

Use [Contributing](../CONTRIBUTING.md) for the usual edit, test and PR workflow.
The commands here cover CI, dependency compatibility and performance work.

## Documentation checks

For documentation changes, run:

```sh
bundle exec rake docs:check
```

This checks local links, spelling, the generated manual and runnable examples
from the usage and configuration guides. It does not need the optional shells
or system manual tools.

CI uses these checks for changes limited to Markdown guides in `docs`, the
configuration example, PNG comparison images, the PR template and the root README,
architecture, contribution, changelog, security and code of conduct documents.
Pull requests also run the commit checks.

Code, dependencies, scripts, workflows, test fixtures, the generated manual and
unrecognized paths run the full suite. CI considers the entire PR, including
deleted and renamed files; an unavailable comparison also runs the full suite.
The required `ci` check verifies that every expected job succeeded before a
change can merge.

Releases always run the full suite, including workflow dry runs. Scheduled runs
check the dependency advisory database.

## Shell tests

Run completion tests in all three shells with:

```sh
bundle exec rake test:shells
```

The task uses local Bash, Zsh and Fish when all are available and Bash can load
bash-completion 2.x. Otherwise, it uses a running Docker engine or, if unavailable,
Podman. `bundle exec rake check` includes this task and requires every shell test
to pass. The shorter `bundle exec rake` run skips unavailable local integrations.

To run in an isolated environment even when the shells are installed:

```sh
bundle exec rake test:shells:container
```

The first build downloads the image and installs the locked bundle; later builds
reuse those layers. Only the project files needed for testing are copied into the
image. Tests run as an unprivileged user with temporary storage and no network.
The container uses its pinned Linux/Ruby environment and `Gemfile.lock`, regardless
of the host Ruby version. CI checks this route as well as native shell integrations
on Linux and macOS.

Set `RICH_RI_CONTAINER_RUNTIME=docker` or `RICH_RI_CONTAINER_RUNTIME=podman` to
select an engine when running in a container. For example:

```sh
RICH_RI_CONTAINER_RUNTIME=podman bundle exec rake test:shells:container
```

## Compatibility checks

The main `Gemfile.lock` fixes development dependencies. CI also resolves current
versions with `bundle update` in a fresh checkout. Run that check in a separate
checkout to keep your working lockfile intact.

To test the minimum runtime dependencies, use Ruby 3.4 with Bash, Zsh, Fish and
bash-completion 2.x installed locally, then run:

```sh
BUNDLE_GEMFILE=gemfiles/legacy.gemfile bundle install
BUNDLE_GEMFILE=gemfiles/legacy.gemfile bundle exec ruby -rrdoc/rdoc -e \
  'RDoc::RDoc.new.document(ARGV)' -- --ri --quiet --op tmp/legacy-ri test/fixtures/example.rb
BUNDLE_GEMFILE=gemfiles/minimum.gemfile bundle install
LEGACY_RI_STORE="$PWD/tmp/legacy-ri" BUNDLE_GEMFILE=gemfiles/minimum.gemfile \
  RICH_RI_REQUIRE_SHELLS=1 bundle exec ruby bin/test-compatibility
```

The first bundle generates a store using RDoc 6.14. The second runs the runtime
tests using the minimum direct dependencies compatible with RDoc 8.1, including
lookup and completion against that older store. Maintenance-only tests and the
optional server/profiler modes use the main bundle; missing-gem behavior is tested
with both bundles. `LEGACY_RI_STORE` selects the test store; `RICH_RI_REQUIRE_SHELLS=1`
requires all shell integrations to be available. This check uses the selected
minimum bundle and local shells; the container task uses the main locked bundle.

When raising a runtime dependency floor, update the minimum Gemfile and
[compatibility policy](compatibility.md) in the same change.

## Performance

```sh
bundle exec ruby bin/benchmark --output /tmp/rich-ri-before.json
# Make the change, then measure again on the same machine and Ruby.
bundle exec ruby bin/benchmark --compare /tmp/rich-ri-before.json
```

The benchmark measures full CLI startup, rendering and completion against a
temporary RI store built from a repository fixture. It discards one warm-up
invocation and reports the median of five runs. `--iterations=N` selects 1 to 50
runs; `--output=FILE` saves the JSON report.

Comparison exits unsuccessfully when a case slows by both more than 30% and
50 ms. Compare under similar load with the same Ruby and dependency versions;
small timing differences are not meaningful. CI uploads a `benchmark` artifact
for each quality run so a reviewer can inspect measurements across changes.
