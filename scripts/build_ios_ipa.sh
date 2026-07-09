#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

ipa_name="${IPA_NAME:-clutter-dev}"
build_dir="$repo_root/build/ios"
runner_app="$build_dir/iphoneos/Runner.app"
staging_dir="$build_dir/$ipa_name"
payload_dir="$staging_dir/Payload"
ipa_path="$build_dir/$ipa_name.ipa"

echo "Building iOS release app..."
flutter build ios --release

if [[ ! -d "$runner_app" ]]; then
  echo "error: expected Runner.app at $runner_app" >&2
  exit 1
fi

echo "Packaging IPA..."
rm -rf "$staging_dir" "$ipa_path"
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
echo "Created $ipa_path ($size)"
