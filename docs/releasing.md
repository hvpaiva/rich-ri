# Releasing

Releases are prepared in a pull request and published from a signed `vX.Y.Z` tag
on main. A tag triggers the complete CI workflow before publication. The release
job uses the `release` environment and RubyGems trusted publishing; no persistent
RubyGems API key belongs in repository secrets.

## First-time setup

Create the public repository `hvpaiva/rich-ri` and push the reviewed source.
Enable vulnerability alerts, Dependabot security updates and private vulnerability
reporting. Create the `skip-changelog` label for maintenance-only pull requests.

Protect main with required pull requests and status checks, block force pushes
and deletion, and require signed commits. Use merge commits to retain the signed
commit history. Select check names from the first successful CI run: quality,
the test matrix, audit, fresh-dependencies and commits. The commits check runs
only on pull requests. Protect release tags against modification and deletion.

Create the GitHub Actions environment `release`, restricting deployment to `v*`
tags. Configure a pending trusted publisher in the RubyGems account that will
own the gem:

| Field | Value |
| --- | --- |
| Gem name | `rich-ri` |
| Repository owner | `hvpaiva` |
| Repository name | `rich-ri` |
| Workflow filename | `release.yml` |
| Environment | `release` |

Recheck name availability before creating the publisher. Pending publishers
expire; configure one shortly before the first release. After the first push it
becomes a regular publisher. See the [RubyGems trusted publishing guide](https://guides.rubygems.org/trusted-publishing/).

Before the first release, run `bundle lock --add-checksums` with network access
and commit the resulting lockfile. This fetches checksums for default gems whose
archives may not exist in a local Ruby installation. Verify the committed result
with `BUNDLE_FROZEN=true bundle check` before preparing the release.

Run Release manually with `dry_run` enabled to check the pipeline. A dry run
builds the package and exercises CI without publishing. It does not replace
checking the account settings above.

## Prepare and publish

Start on a clean branch based on main. Review the `Unreleased` entries, then run:

```sh
bin/release 0.1.0
bundle exec rake check
```

The preparation command updates the version, dependency lock, dated changelog
and manual. It does not commit, tag, push or publish. Review the diff and open a
pull request with a `chore: prepare 0.1.0 release` commit. Wait for green checks
and review before merging.

After updating your local main to the merge commit:

```sh
git tag -s v0.1.0 -m 'Release 0.1.0'
git push origin v0.1.0
```

The workflow checks tag/version/changelog agreement and main ancestry, reruns CI,
builds the gem and publishes through OIDC. `rake release` refuses to publish
outside the GitHub release workflow. The GitHub release includes curated notes
and the gem archive. After the first successful publication, update the README
installation section to lead with `gem install rich-ri`.

Verify the RubyGems version, install into a clean Ruby environment, and exercise
lookup and completion. Keep the tag immutable once users can install it.

## Recover

If verification fails, fix the cause before publishing. Do not move a published
tag. If RubyGems has the version but the GitHub release step failed, create the
GitHub release from that existing tag and upload the same gem; do not republish
the RubyGems version. A correction to a published package needs a new version.

For a security issue, coordinate privately as described in [SECURITY.md](../SECURITY.md).
Publish a corrected version, describe the impact, and consider yanking an unsafe
version. Yanking can break consumers, so communicate the replacement and reason.
