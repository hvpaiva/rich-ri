# Maintenance

## Release infrastructure

`bundle exec rake github:verify` checks branch and tag protections, required CI
checks, the release environment and security settings. `rake github:setup`
applies the project policy. Both require repository administrator access.

Publication uses [RubyGems Trusted Publishing](https://guides.rubygems.org/trusted-publishing/).
The publisher must match repository `hvpaiva/rich-ri`, workflow `release.yml`
and environment `release`. Update that binding in RubyGems if the integration
changes. `github:verify` checks GitHub settings only.

## Release

From a clean, up-to-date `main`, with `gh` authenticated and Git signing configured:

```sh
bin/release X.Y.Z --push
```

The command prepares the version, changelog and manual, runs the checks, opens a
release PR, waits for CI, merges, and pushes a signed tag for the merge commit.
It then watches the Release workflow. Omit `--push` to stop at the PR;
`--dry-run` previews preparation without writing files or publishing.

The workflow reruns CI, validates the tag and branch ancestry, builds one gem,
and tests installation of that file. It records a SHA-256 checksum and a GitHub
build attestation. The publication and GitHub Release jobs download that artifact
and verify its checksum. RubyGems authentication uses short-lived OIDC credentials.
`rake release` publishes the verified artifact and refuses local execution.

To rehearse the workflow without publishing a gem or creating a GitHub Release:

```sh
gh workflow run release.yml --ref main -f dry_run=true
```

Inspect the run in Actions. The rehearsal exercises CI, packaging, installation,
artifact transfer and attestation; it does not request RubyGems credentials.
It cannot validate the publisher's authentication with RubyGems.

## Verify a download

Download the gem and `SHA256SUMS` from its GitHub Release, then run:

```sh
sha256sum --check SHA256SUMS
gh attestation verify rich-ri-X.Y.Z.gem --repo hvpaiva/rich-ri --source-ref refs/tags/vX.Y.Z
```

On macOS, use `shasum -a 256 --check SHA256SUMS`. The attestation binds the artifact
to its source and workflow. Release tags and published GitHub releases are immutable.

## Recover an interrupted release

Run the same `bin/release` command again. It inspects existing branches, PRs,
commits and tags before continuing. It never replaces an existing tag.

If a workflow failed before publication, correct the problem and follow the
printed retry command. If RubyGems publication succeeded and only GitHub Release
creation failed, retry that job alone. When the publication result is uncertain,
check RubyGems before retrying: an accepted version must not be pushed again.

## Urgent fixes

Only the latest released version receives fixes. If `main` contains unfinished
work for the next release, start a hotfix branch at the latest released tag.
For example, to fix `0.2.0` while `main` is preparing `0.3.0`:

```sh
git switch -c hotfix/0.2 v0.2.0
git push -u origin hotfix/0.2
```

Create a topic branch from it and submit the fix as a PR against `hotfix/0.2`.
Hotfix branches have the same protections as `main`. After the fix is merged,
update the local hotfix branch and run:

```sh
bin/release 0.2.1 --branch hotfix/0.2 --push
```

The release must match the branch's major and minor version. Bring the fix and
release notes back to `main` through a separate PR, preserving changes still under
`Unreleased` and keeping dated changelog entries newest first.

If a published version must be withdrawn, publish a fixed version first when
possible. Explain the withdrawal in its changelog entry, then use
`gem yank rich-ri -v X.Y.Z` with your personal RubyGems credentials and MFA.
Trusted publishing only grants push access. A withdrawn version cannot be reused;
publish a new version number for the replacement.

## Dependencies and access

Dependabot proposes gem and test-image updates weekly and action updates monthly. Review the
upstream changes and run the same checks as other PRs. A runtime dependency change
may need a changelog entry even when Dependabot supplied `skip-changelog`.
Update `gemfiles/minimum.gemfile` when raising a supported dependency floor.
The scheduled audit checks the lockfile for known vulnerabilities.

Review repository administrators, RubyGems owners and publisher configuration
when maintainers change. Keep account recovery methods current and transfer both
services when handing over the project. Review changes to release code and
workflows with particular care; they run with publication or attestation permissions.
