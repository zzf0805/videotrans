# AGENTS.md

## Project Shape
- Flutter desktop app; first release intentionally supports only macOS arm64 and Windows x64.
- Core app code is in `lib/`; platform runners are the generated Flutter `macos/` and `windows/` projects.
- Do not add fallback to system `ffmpeg`, Homebrew, Python, or `PATH`; the app must use bundled binaries only.

## Bundled FFmpeg
- Required assets are declared in `pubspec.yaml` and must exist at:
  - `assets/bin/macos-arm64/ffmpeg`
  - `assets/bin/macos-arm64/ffprobe`
  - `assets/bin/windows-x64/ffmpeg.exe`
  - `assets/bin/windows-x64/ffprobe.exe`
- `lib/services/ffmpeg_bundle.dart` copies these assets to app support storage before execution; macOS binaries are `chmod +x` there.
- Windows packaging must include the Flutter `data/` directory; do not distribute only the `.exe`.

## Video Rules
- Keep conversion behavior aligned with `/Users/zzf/Documents/check_faststart.py` unless the user explicitly changes the source script.
- Supported input extensions are `.mp4`, `.m4v`, `.mov`.
- Only-faststart fixes use remux: `-c copy -movflags +faststart -brand mp42`.
- Any bitrate/profile/level/pix_fmt issue triggers H.264 compatibility transcode: Main, Level 3.1, `yuv420p`, 30 fps, `1200k`, maxrate `1500k`, bufsize `2400k`, preset `medium`, bt709 tags, AAC `128k`, faststart, `mp42` brand.
- Output goes to a separate output folder and must not overwrite originals; duplicate output names get numeric suffixes.

## Commands
- Fetch packages: `flutter pub get`
- Format: `dart format lib test`
- Static checks: `flutter analyze`
- Tests: `flutter test`
- macOS build: `flutter build macos --release`
- Windows build must be run on Windows: `flutter build windows --release`
