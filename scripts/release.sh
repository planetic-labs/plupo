#!/bin/bash
# Prepare and publish a release from committed main. GitHub Actions builds the DMG.
set -euo pipefail

usage() {
  echo 'Usage: bash scripts/release.sh [--dry-run] MAJOR.MINOR.PATCH'
  echo 'Commit your changes first. --dry-run validates without changing or publishing anything.'
}
fail() { echo "Release stopped: $*" >&2; exit 1; }
dry_run=false
if [[ "${1:-}" == --dry-run ]]; then dry_run=true; shift; fi
if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then usage; exit 0; fi
[[ $# == 1 ]] || { usage >&2; exit 1; }
version=$1
[[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || fail 'Use a version such as 0.1.3, without a v prefix or leading zeros.'
tag="v$version"
cd "$(dirname "$0")/.."
for command in git python3 xcodebuild xcrun; do
  command -v "$command" >/dev/null || fail "Required command not found: $command"
done
[[ "$(git symbolic-ref --quiet --short HEAD)" == main ]] || fail 'Switch to main before releasing.'
[[ -z "$(git status --porcelain --untracked-files=all)" ]] || fail 'Commit or set aside all modified and untracked files before releasing.'
project=Plupo.xcodeproj/project.pbxproj
[[ -f "$project" && -f Tests/run.sh ]] || fail 'Project or regression checks are missing.'
git remote get-url origin >/dev/null || fail 'Remote origin is missing.'
remote_refs=$(git ls-remote --refs origin refs/heads/main 'refs/tags/v*') || fail 'Could not read origin. Check your connection and GitHub access.'
remote_main=$(printf '%s\n' "$remote_refs" | awk '$2 == "refs/heads/main" {print $1}')
[[ -n "$remote_main" ]] || fail 'origin/main is missing.'
git cat-file -e "$remote_main^{commit}" 2>/dev/null || fail 'Fetch and update main from origin before releasing.'
git merge-base --is-ancestor "$remote_main" HEAD || fail 'Local main is behind or diverged from origin/main. Update it first.'
! git show-ref --verify --quiet "refs/tags/$tag" || fail "Local tag $tag already exists."
if printf '%s\n' "$remote_refs" | awk '{print $2}' | /usr/bin/grep -Fxq "refs/tags/$tag"; then
  fail "Remote tag $tag already exists."
fi
local_tags=$(git tag --list 'v*')
# Compare numeric components rather than strings: 0.1.10 is newer than 0.1.9.
RELEASE_VERSION="$version" RELEASE_REMOTE_REFS="$remote_refs" RELEASE_LOCAL_TAGS="$local_tags" python3 - <<'PY'
import os, re
from pathlib import Path

def parts(value):
    return tuple(map(int, value.split('.')))

version = os.environ['RELEASE_VERSION']
target = parts(version)
project = Path('Plupo.xcodeproj/project.pbxproj').read_text()
current = re.findall(r'MARKETING_VERSION = ([0-9]+\.[0-9]+(?:\.[0-9]+)?);', project)
if not current or len(set(current)) != 1:
    raise SystemExit('Release stopped: Xcode marketing versions are missing or inconsistent.')
installed = parts(current[0])
installed += (0,) * (3 - len(installed))
if target < installed:
    raise SystemExit(f'Release stopped: {version} is older than the project version {current[0]}.')
tags = os.environ['RELEASE_LOCAL_TAGS'].splitlines()
tags += [line.split('\t')[-1][len('refs/tags/'):]  for line in os.environ['RELEASE_REMOTE_REFS'].splitlines() if '\trefs/tags/' in line]
for tag in tags:
    if re.fullmatch(r'v[0-9]+\.[0-9]+\.[0-9]+', tag) and target <= parts(tag[1:]):
        raise SystemExit(f'Release stopped: version must be newer than existing tag {tag}.')
print(f'Release plan: project {current[0]} → {version}; publish {"v" + version}.')
PY
if [[ "$dry_run" == true ]]; then
  echo 'Dry run passed. No tests, builds, commits, tags, or pushes were performed.'
  echo 'A real run will test, build, update the Xcode version, commit if needed, and atomically push main and the new tag.'
  exit 0
fi

echo 'Running regression checks…'
bash Tests/run.sh
echo 'Verifying the Release build…'
xcodebuild -project Plupo.xcodeproj -scheme Plupo \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/release-check CODE_SIGNING_ALLOWED=NO \
  MARKETING_VERSION="$version" build
[[ -z "$(git status --porcelain --untracked-files=all)" ]] || fail 'Files changed during verification. Review and commit them before retrying.'
RELEASE_VERSION="$version" python3 - <<'PY'
import os, re
from pathlib import Path
p = Path('Plupo.xcodeproj/project.pbxproj')
p.write_text(re.sub(r'MARKETING_VERSION = [0-9]+\.[0-9]+(?:\.[0-9]+)?;', f'MARKETING_VERSION = {os.environ["RELEASE_VERSION"]};', p.read_text()))
PY
if ! git diff --quiet -- "$project"; then
  git add -- "$project"
  git -c user.name='Plupo Contributors' -c user.email='contributors@plupo.invalid' \
    commit -m "Release $tag" -- "$project"
fi
git -c user.name='Plupo Contributors' -c user.email='contributors@plupo.invalid' \
  tag -a "$tag" -m "Plupo $version"
# If the branch cannot be updated, the tag must not start a release by itself.
if ! git push --atomic origin HEAD:refs/heads/main "refs/tags/$tag"; then
  echo 'Push failed. The local release commit and tag were kept for inspection.' >&2
  echo "After resolving the cause, retry: git push --atomic origin HEAD:refs/heads/main refs/tags/$tag" >&2
  exit 1
fi
echo "Published $tag. GitHub Actions will now build and publish the DMG."
echo 'Check progress: https://github.com/planetic-labs/plupo/actions/workflows/build.yml'
