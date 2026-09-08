<p align="center">
  <img src="catMedia/Assets.xcassets/AppIcon.appiconset/catMediaDark-iOS-Default-1024x1024@1x.png" width="160" alt="catMedia app icon">
</p>

<h1 align="center">catMedia</h1>

<p align="center">Offline media inspection, conversion, and extraction for iOS.</p>

An offline iOS media utility for inspecting metadata, converting files, and extracting audio or video streams with FFmpeg.

## Features

- Media metadata inspection through FFprobe
- Conversion to supported MP4 presets
- Video or audio stream extraction
- Local processing with no cloud upload
- Output files stored in the app's Documents directory
- Dark, focused SwiftUI interface

## Requirements

- macOS with Xcode 16.4 or newer
- iOS 16.0 or newer
- Xcode command-line tools
- An Apple Developer account for device installation

## Setup

1. Clone the repository.
2. Open `catMedia.xcodeproj` in Xcode.
3. Build the bundled FFmpeg libraries:

```bash
scripts/ffmpeg/fetch_official_ffmpeg.sh
scripts/ffmpeg/build_ios_minimal.sh
```

4. Select the `catMedia` scheme and an iOS device or simulator.
5. Build and run.

The FFmpeg build output is generated under `Vendor/FFmpeg/` and is intentionally ignored by Git because it contains generated libraries and can be rebuilt locally.

## Project structure

```text
catMedia/
├── Models/       Media metadata and conversion options
├── Services/     FFmpeg, FFprobe, file, and output services
├── ViewModels/   Async workflow and progress state
├── Views/        SwiftUI screens and reusable UI components
└── Utils/        Command construction helpers
```

## Development notes

- Keep media work off the main thread and publish UI state on the main actor.
- Do not commit generated FFmpeg output, Xcode derived data, or local user settings.
- Keep UI animation short, interruptible, and limited to purposeful feedback.
- Test imports, metadata parsing, conversion, extraction, and output-file validation before release.

## License

This project is licensed under the [MIT License](LICENSE).
