#!/usr/bin/env bash

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
kit="${root}/third_party/ffmpeg-kit-next"

if ! command -v nix >/dev/null 2>&1; then
  echo "nix is required to build ffmpegkitnext" >&2
  exit 1
fi

platforms=("$@")
if ((${#platforms[@]} == 0)); then
  platforms=(android ios macos)
fi

for platform in "${platforms[@]}"; do
  case "${platform}" in
    android)
      "${kit}/nix-android.sh" -p android-r27d -- --enable-lame
      ;;
    ios)
      "${kit}/nix-ios.sh" -p xcode26 -x -- --enable-lame
      ;;
    macos)
      "${kit}/nix-macos.sh" -p xcode26 -x -- --enable-lame
      ;;
    *)
      echo "unsupported ffmpegkitnext flutter platform: ${platform}" >&2
      exit 1
      ;;
  esac
done

"${kit}/flutter/flutter/copy_local_binaries.sh" "${platforms[@]}"
