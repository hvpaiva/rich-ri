# Development checks

Use [Contributing](../CONTRIBUTING.md) for the usual edit, test and PR workflow.
The commands here cover dependency compatibility and performance work.

## Compatibility checks

The main `Gemfile.lock` fixes development dependencies. CI also resolves current
versions with `bundle update` in a fresh checkout. Run that check in a separate
checkout to keep your working lockfile intact.

To test the minimum runtime dependencies, use Ruby 3.4 and run:

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
lookup and completion against that older store. Maintenance-only tests use the
main bundle. `LEGACY_RI_STORE` selects the test store; `RICH_RI_REQUIRE_SHELLS=1`
requires all shell integrations to be available.

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
