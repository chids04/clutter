#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$repo_root"

echo "building ffmpeg dependency"
"${repo_root}/scripts/setup_ffmpeg_kit.sh" ios

echo "refreshing ios pods for the rebuilt xcframeworks"
flutter pub get
pod install --project-directory=ios

ipa_name="${IPA_NAME:-clutter-dev}"
bundle_id="${BUNDLE_ID:-com.chx.clutter.dev}"
build_dir="$repo_root/build/ios"
runner_app="$build_dir/iphoneos/Runner.app"
staging_dir="$build_dir/$ipa_name"
payload_dir="$staging_dir/Payload"
ipa_path="$build_dir/$ipa_name.ipa"
zip_path="$build_dir/$ipa_name.zip"

echo "building unsigned ios release app"
flutter build ios --release --no-codesign

if [[ ! -d "$runner_app" ]]; then
  echo "error: expected Runner.app at $runner_app" >&2
  exit 1
fi

echo "setting bundle identifier to $bundle_id"
plutil -replace CFBundleIdentifier -string "$bundle_id" \
  "$runner_app/Info.plist"

echo "packaging ipa"
rm -rf "$staging_dir" "$ipa_path"
rm -f "$zip_path"
mkdir -p "$payload_dir"
cp -R "$runner_app" "$payload_dir/Runner.app"

(
  cd "$staging_dir"
  zip -qry "$ipa_path" Payload
)

if [[ ! -f "$ipa_path" ]]; then
  echo "error: failed to create $ipa_path" >&2
  exit 1
fi

size="$(du -h "$ipa_path" | awk '{print $1}')"
echo "created $ipa_path ($size)"

echo "wrapping ipa for airdrop"
zip -qj "$zip_path" "$ipa_path"

if ! unzip -tq "$zip_path" >/dev/null; then
  echo "error: failed to verify $zip_path" >&2
  exit 1
fi

zip_size="$(du -h "$zip_path" | awk '{print $1}')"
echo "created $zip_path ($zip_size)"
