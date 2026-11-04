# Releasing Plupo

GitHub Actions builds an Apple Silicon DMG only when a version tag is pushed or the workflow is started manually. Ordinary branch pushes and pull requests do not trigger builds.

For a manual build, open **Actions → Build and release Plupo → Run workflow**. Manual builds are retained as workflow artifacts for seven days and do not publish a release.

## Release with one command

Commit all intended changes on `main` first, including the release script itself on its first use. You need Xcode with its command-line tools selected, Python 3, and Git access to `origin`. Then choose a new version, for example:

```sh
bash scripts/release.sh 0.1.3
```

The script verifies that the working tree is clean, the current branch is `main`, and local history contains `origin/main`. It checks both local and remote version tags and rejects reused or older versions. It runs `Tests/run.sh` and a local unsigned ARM64 Release build before changing the version. It then updates every Xcode `MARKETING_VERSION`, creates a version commit if needed, creates an annotated tag, and atomically pushes `main` and the tag. Local commits ahead of `origin/main` are included in that push. The version in Xcode and the version used by update checks therefore stay in sync.

To validate the release plan without running tests, building, or changing/publishing anything:

```sh
bash scripts/release.sh --dry-run 0.1.3
```

The dry run still needs network access to read remote refs. A failed verification leaves the version and tags untouched. If publication is rejected, the local release commit and tag are kept and the script prints an exact push command to retry after resolving the cause. Do not rerun the whole script with that same version: the existing local tag will correctly block it. No reset, force push, or tag deletion is performed automatically.

After a successful push, **Build and release Plupo** builds the public ad-hoc-signed DMG on GitHub and publishes `Plupo-arm64.dmg` and `SHA256SUMS.txt`. The script finishing means publication was triggered; check Actions for the final build/release result. Existing release assets are not silently replaced on a rerun. Install the new DMG to verify the version and update-check behavior.

The release script can be tested independently, without Xcode builds, network access, or real releases, using `python3 Tests/ReleaseScriptTests.py`. These checks use disposable local Git remotes and stub the app tests/build; they verify release orchestration rather than application functionality.

## Automatic retries for unavailable GitHub Macs

**Retry release runner failures** runs on Ubuntu after the release workflow finishes unsuccessfully. It retries only version-tag push runs whose **Build Apple Silicon DMG** job has no steps and carries GitHub's explicit hosted-runner acquisition failure annotation. The release job must have been skipped. Compilation, packaging, upload, publication, and ordinary cancellation failures are not retried.

There are at most four attempts per run: the original plus three retries. Existing manual retries count toward this limit. A retry reuses the original tag and commit and restarts failed jobs and their dependents; it does not create a new version or change release assets. Once the limit is reached, the automation records the reason in its Actions summary and stops. No specific time of day or runner availability is guaranteed.

The workflow reads trusted automation from the default branch, does not execute code or download artifacts from the failed run, and uses the built-in token with Actions write and Checks read permissions. No personal token or additional secrets are required. To inspect an existing run, use **Run workflow**, enter its numeric run ID, and leave **dry_run** enabled. Disable it only to retry an eligible completed failure. Active or successful runs are always skipped. Local logic tests: `python3 Tests/RetryRunnerFailureTests.py`.

Releases are titled `Plupo vMAJOR.MINOR.PATCH`. GitHub automatically generates release notes with merged pull requests, contributors, and a link to the full comparison with the previous release. Installation and first-launch instructions appear above the generated notes. Use descriptive pull request titles so the change list is useful to users; direct commits can be reviewed through the comparison link.

DMG packaging uses pinned Python tools (`dmgbuild`, `ds-store`, and `mac-alias`) in an isolated environment. These tools are not shipped with the app. The Finder background, icon positions, and window size are defined in `scripts/dmg/`. To regenerate the Retina background after editing its source, run `swift scripts/dmg/render-background.swift`. The app and Applications shortcut are the two visible items; the license and first-launch text remain on the disk as hidden support files.

The workflow uses GitHub-hosted Apple Silicon runners with Xcode 26.3, builds in Release mode, verifies ARM64 output and the ad-hoc signature, and verifies the disk image. The release job alone has permission to write repository contents. No Apple ID, Developer ID certificate, notarization credentials, or custom repository secrets are needed.

Ad-hoc signing is a local integrity signature, not verification of the publisher by Apple. Keep the first-launch notice in the README, release notes, and DMG until Developer ID signing and notarization are added.

To check packaging locally on an Apple Silicon Mac with Xcode selected:

```sh
bash scripts/package-dmg.sh 0.1.1
```

Output is written to `build/distribution/`. Ship only the DMG and checksum, not build logs, DerivedData, debug symbols, certificates, or local configuration. Public release builds should come from GitHub Actions to avoid distributing personal paths from local build machines.

Use a project identity for release commits, for example:

```sh
git -c user.name='Plupo Contributors' \
  -c user.email='contributors@plupo.invalid' commit
```

Before publishing, mount the DMG and check that it contains Plupo, the Applications shortcut, the license, and the installation instructions. A successful build does not replace interactive drag-and-drop QA on macOS.

## Dependency updates

Dependabot checks GitHub Actions and the DMG packaging requirements monthly, on the first day of the month at 10:00 Europe/Moscow. Updates are grouped into one pull request per ecosystem, with at most one open version-update pull request for each. No automatic merging is configured. Review updates before merging; use a manual workflow run to check packaging when needed. Dependabot pull requests and ordinary commits do not trigger the app build or publish a release.

## Swift security analysis

The **Monthly Swift security scan** workflow runs CodeQL's extended security queries against the Swift application on the first day of each month at 11:17 Europe/Moscow. It can also be started manually from Actions. Pushes, pull requests, and release tags do not trigger this scan.

CodeQL runs on a GitHub-hosted Intel Mac with Xcode 26.3 to avoid Rosetta overhead in the analyzer, while explicitly cross-compiling the application for ARM64 without signing. Release packaging continues to run on Apple Silicon. This build is only for analysis: it does not package a DMG or publish a release. Findings appear under **Security → Code scanning**. Dependabot maintains the pinned CodeQL action along with the other GitHub Actions.
