#!/usr/bin/env bash
#
# Build an UNSIGNED iOS IPA locally on macOS.
#
# This script runs the same steps as the GitHub Actions workflow
# .github/workflows/ios-ipa.yml, but on your own Mac:
#   flutter pub get
#   flutter build ios --release --no-codesign
#   Payload/Runner.app -> dist/DSH-Remote-unsigned.ipa
#
# Usage:
#   tools/build_ios.sh
#
# Output:
#   dist/DSH-Remote-unsigned.ipa          unsigned IPA, not installable as-is
#   dist/DSH-Remote-unsigned.ipa.sha256   its SHA-256
#
# The IPA must be signed on the iPhone with your own certificate before it can
# be installed. See docs/IOS-BUILD.md for the signing/install flow.
#
# Requirements: macOS, Xcode (with command line tools), Flutter 3.47.7 stable.
#
# Compatibility: written for the bash 3.2 that ships with macOS (no bash 4
# features: no associative arrays, no ${var,,}, no mapfile).

set -euo pipefail

EXPECTED_FLUTTER="3.47.7"
IPA_NAME="DSH-Remote-unsigned.ipa"
APP_PATH="build/ios/iphoneos/Runner.app"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '\n==> %s\n' "$*"; }

# --- Preconditions -----------------------------------------------------------

if [ "$(uname -s)" != "Darwin" ]; then
  die "iOS builds require macOS (this host is $(uname -s)). Use the GitHub Actions workflow instead: docs/IOS-BUILD.md"
fi

command -v flutter >/dev/null 2>&1 || die "flutter is not on PATH. Install Flutter ${EXPECTED_FLUTTER} (stable) and add its bin/ to PATH."
command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild is not on PATH. Install Xcode, then run: sudo xcode-select -s /Applications/Xcode.app"

[ -f pubspec.yaml ] || die "pubspec.yaml not found in ${ROOT}; run this script from the Flutter project."

actual_flutter="$(flutter --version 2>/dev/null | sed -n '1s/^Flutter \([0-9][0-9.]*\).*/\1/p' || true)"
if [ -z "${actual_flutter}" ]; then
  printf 'warning: could not determine the local Flutter version; CI pins %s.\n' "${EXPECTED_FLUTTER}" >&2
elif [ "${actual_flutter}" != "${EXPECTED_FLUTTER}" ]; then
  printf 'warning: local Flutter %s differs from the CI pin %s; build output may differ.\n' "${actual_flutter}" "${EXPECTED_FLUTTER}" >&2
fi

app_version="$(awk '$1 == "version:" { print $2; exit }' pubspec.yaml)"
info "App version: ${app_version:-unknown}"
info "Xcode: $(xcodebuild -version 2>/dev/null | sed -n '1p' || true)"

# --- Build -------------------------------------------------------------------

info "flutter pub get"
flutter pub get

info "flutter build ios --release --no-codesign"
flutter build ios --release --no-codesign

if [ ! -d "${APP_PATH}" ]; then
  die "build output missing: ${APP_PATH}. The build above failed or produced a different layout; rerun with 'flutter build ios --release --no-codesign -v'."
fi

info "Built app: ${APP_PATH}"
ls -ld "${APP_PATH}"
if [ -x /usr/libexec/PlistBuddy ]; then
  printf '    bundle id:  %s\n' "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${APP_PATH}/Info.plist")"
  printf '    version:    %s (%s)\n' \
    "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_PATH}/Info.plist")" \
    "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${APP_PATH}/Info.plist")"
fi

# --- Package Payload/Runner.app as an IPA ------------------------------------

info "Packaging Payload/Runner.app"

stage="$(mktemp -d "${TMPDIR:-/tmp}/dsh-ios-ipa.XXXXXX")"
cleanup() { rm -rf "${stage}"; }
trap cleanup EXIT

mkdir -p "${stage}/Payload"
cp -R "${APP_PATH}" "${stage}/Payload/Runner.app"

mkdir -p dist
ipa="${ROOT}/dist/${IPA_NAME}"
rm -f "${ipa}" "${ipa}.sha256"
# -r: recurse; -y: store symlinks as symlinks (needed by versioned framework
# layouts inside Frameworks/*.framework).
( cd "${stage}" && zip -q -r -y "${ipa}" Payload )

if [ ! -s "${ipa}" ]; then
  die "packaging failed: ${ipa} is missing or empty"
fi

size_bytes="$(wc -c < "${ipa}" | tr -d '[:space:]')"
size_mib="$(awk -v bytes="${size_bytes}" 'BEGIN { printf "%.1f", bytes / 1048576 }')"

echo
echo "IPA contents (head):"
unzip -l "${ipa}" | sed -n '1,12p'
echo
printf 'IPA:         %s\n' "${ipa}"
printf 'Size:        %s bytes (%s MiB)\n' "${size_bytes}" "${size_mib}"
printf 'SHA-256:     '
# Record the digest with a bare filename so `shasum -a 256 -c` works next to it.
( cd dist && /usr/bin/shasum -a 256 "${IPA_NAME}" | tee "${IPA_NAME}.sha256" )

cat <<'EOF'

The IPA is UNSIGNED and cannot be installed as-is:
  1. Copy dist/DSH-Remote-unsigned.ipa to the iPhone (AirDrop, Files, iCloud Drive).
  2. Sign and install it on-device with BuildBox 2.0, or another signer
     (ESign / SideStore / AltStore) using your .p12 + .mobileprovision.
  3. Full walkthrough: docs/IOS-BUILD.md
EOF
