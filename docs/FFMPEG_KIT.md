# ffmpegkitnext setup

clutter pins ffmpegkitnext `v8.1.0` as a git submodule. upstream only ships source, so the android, ios, and macos binaries must be built locally before running video import or audio cropping.

install nix, initialise submodules, then run:

```sh
git submodule update --init --recursive
./scripts/setup_ffmpeg_kit.sh
```

individual platforms can be selected:

```sh
./scripts/setup_ffmpeg_kit.sh android
./scripts/setup_ffmpeg_kit.sh ios macos
```

the script follows the upstream flutter build steps, enables lame for mp3 extraction and cropped output, and copies the generated aar or xcframework files into the local flutter plugin. waveform rendering uses ffmpeg's built-in filters. generated native binaries stay ignored by git and must also be produced in ci.

the build intentionally does not enable ffmpegkitnext's gpl option. keep the ffmpegkitnext, ffmpeg, and lame license notices with distributed applications and re-check the final native build configuration before release.
