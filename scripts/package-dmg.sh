#!/bin/bash
set -euo pipefail

# Builds a public universal preview using ad-hoc signing, without Apple credentials.
version=${1:-0.0.0}
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo 'Version must have the form 0.1.0.' >&2
  exit 1
fi
cd "$(dirname "$0")/.."
output_dir="$PWD/build/distribution"
derived_dir="$PWD/build/DerivedData"
staging_dir=$(mktemp -d "${TMPDIR:-/tmp}/plupo-dmg.XXXXXX")
trap 'rm -rf "$staging_dir"' EXIT
mkdir -p "$output_dir"

xcodebuild -project Plupo.xcodeproj -scheme Plupo \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath "$derived_dir" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= \
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  CODE_SIGN_ENTITLEMENTS="$PWD/scripts/distribution.entitlements" \
  MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION=1 \
  DEBUG_INFORMATION_FORMAT=dwarf SWIFT_SERIALIZE_DEBUGGING_OPTIONS=NO \
  build

app="$derived_dir/Build/Products/Release/Plupo.app"
codesign --verify --deep --strict "$app"
architectures=$(lipo -archs "$app/Contents/MacOS/Plupo")
if [[ "$architectures" != "arm64 x86_64" && "$architectures" != "x86_64 arm64" ]]; then
  echo "Unexpected architectures: $architectures" >&2
  exit 1
fi
# Shipping only the app avoids Xcode logs, debug symbols and local configuration.
ditto "$app" "$staging_dir/Plupo.app"
ln -s /Applications "$staging_dir/Applications"
cp LICENSE "$staging_dir/LICENSE.txt"
cat > "$staging_dir/Read Me.txt" <<'NOTES'
Plupo — Drag. Drop. Keep moving.

Requires macOS 14.0 or later and an Apple Silicon or Intel Mac.
Drag Plupo into Applications, eject this disk image, then open Plupo.

This early preview has an ad-hoc signature, not an Apple Developer ID
signature, and has not been notarized by Apple. macOS may block first launch.
If you trust this download, try opening it once, then go to System Settings
> Privacy & Security > Open Anyway and confirm.
Do not disable Gatekeeper or other system-wide security protections.

Plupo is in early development. Features and behavior may change.
Source, known limitations and issue reports:
https://github.com/planetic-labs/plupo

Released under the MIT License; see LICENSE.txt.
NOTES

# A dedicated environment keeps packaging dependencies out of the app.
packaging_dir="$PWD/build/dmg-tools"
if [[ ! -x "$packaging_dir/bin/python" ]]; then
  python3 -m venv "$packaging_dir"
fi
"$packaging_dir/bin/python" -m pip install --disable-pip-version-check \
  -r scripts/dmg/requirements.txt
"$packaging_dir/bin/python" -m dmgbuild -s scripts/dmg/settings.py \
  -D "staging=$staging_dir" Plupo "$output_dir/Plupo-universal.dmg"
hdiutil verify "$output_dir/Plupo-universal.dmg"
(cd "$output_dir" && shasum -a 256 Plupo-universal.dmg > SHA256SUMS.txt)
echo "Created $output_dir/Plupo-universal.dmg"
