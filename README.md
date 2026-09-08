# catMedia

This app now uses official FFmpeg source from the upstream repository instead of third-party iOS wrapper packages.

## Official FFmpeg iOS flow

1. Clone official FFmpeg:

```bash
scripts/ffmpeg/fetch_official_ffmpeg.sh
```

2. Build static iOS libraries (device + simulator):

```bash
scripts/ffmpeg/build_ios_minimal.sh
```

This script performs the same flow you requested and uses a compatibility-first FFmpeg configure profile:

- clone official FFmpeg
- set iOS SDK and compiler
- run `make clean`
- run `./configure` for iOS cross-compile
- run `make` and `make install`

The configure profile keeps FFmpeg/FFprobe enabled and does not force a tiny `--disable-everything` build, so broader media containers/codecs are usable.

The install output is created at:

- `Vendor/FFmpeg/FFmpeg/ios-build`
- Device libs: `Vendor/FFmpeg/FFmpeg/ios-build/iphoneos/lib`
- Simulator libs: `Vendor/FFmpeg/FFmpeg/ios-build/iphonesimulator/lib`

## Xcode integration

Project settings are configured to use:

- Header Search Paths: `$(PROJECT_DIR)/Vendor/FFmpeg/FFmpeg/ios-build/include`
- Library Search Paths: `$(PROJECT_DIR)/Vendor/FFmpeg/FFmpeg/ios-build/$(PLATFORM_NAME)/lib`
- Linker flags: `-lcatmediafftools -lavdevice -lavfilter -lavcodec -lavformat -lavutil -lswresample -lswscale -lz -lbz2 -liconv -lc++`

## Wrapper and Swift bridge

The project includes:

- `catMedia/Services/OfficialFFmpegBridge.c`
- `catMedia/Services/OfficialFFmpegBridge.h`
- `catMedia/catMedia-Bridging-Header.h`
- `catMedia/Services/OfficialFFmpegBridge.swift`

`FFmpegCommandRunner` now executes through this local bridge instead of `FFmpeg-iOS`.
