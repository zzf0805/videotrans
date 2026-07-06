# 视频标准化工具

一个 Flutter 桌面应用，用于把本地 MP4/MOV 视频批量处理成更适合在线播放和旧设备兼容的标准格式。

首版只支持：

- macOS Apple Silicon，即 macOS arm64
- Windows x64

## 功能

- 拖入视频或文件夹批量导入。
- 支持窗口任意位置拖入，界面中间区域会高亮提示。
- 支持 `.mp4`、`.m4v`、`.mov`。
- 一键检查视频是否需要处理。
- 一键按队列转换，同时只转换 1 个视频。
- 支持停止转换；再次点击“一键全部转换”会从未完成的视频继续。
- 输出到单独输出文件夹，不覆盖原视频。
- 输出文件统一加 `_trans` 后缀，重名时自动加数字。
- 内置 ffmpeg/ffprobe，不依赖本机 Python、Homebrew、PATH 或系统 ffmpeg。

## 检查和转换规则

转换逻辑对齐 `/Users/zzf/Documents/check_faststart.py`。

检查项：

- `moov` atom 是否在 `mdat` 前面，即 faststart。
- 视频码率是否超过 `1.2 Mbps * 1.1`。
- H.264 Profile 是否为 Main。
- H.264 Level 是否 >= 4.0。
- 像素格式是否为 `yuv420p`。

处理策略：

- 只有 faststart 异常时，执行无损 remux。
- 只要码率、Profile、Level、pix_fmt 任意一项不符合要求，就转码为 H.264 Main Level 3.1 + yuv420p。

兼容转码参数：

- H.264 Main Profile
- Level 3.1
- `yuv420p`
- 30 fps
- 目标码率 `1200k`
- maxrate `1500k`
- bufsize `2400k`
- preset `medium`
- bt709 色彩标记
- AAC `128k`
- faststart
- `mp42` brand

## 内置 ffmpeg

必需文件：

```text
assets/bin/macos-arm64/ffmpeg
assets/bin/macos-arm64/ffprobe
assets/bin/windows-x64/ffmpeg.exe
assets/bin/windows-x64/ffprobe.exe
```

应用启动时会把这些二进制复制到应用支持目录后执行。macOS 下会自动处理可执行权限、quarantine 属性和 ad-hoc 签名。

不要添加系统 ffmpeg、Homebrew、Python 或 PATH fallback。

## 开发命令

安装依赖：

```bash
flutter pub get
```

运行 macOS 版本：

```bash
flutter run -d macos
```

格式化：

```bash
dart format lib test tool
```

静态检查：

```bash
flutter analyze
```

测试：

```bash
flutter test
```

## 打包

macOS release：

```bash
flutter build macos --release
```

产物通常位于：

```text
build/macos/Build/Products/Release/videotrans.app
```

Windows release 必须在 Windows x64 机器上执行：

```powershell
flutter build windows --release
```

Windows 分发时不要只复制 `.exe`，需要分发整个 release 目录，尤其是 Flutter 的 `data/` 目录和相关 DLL。

## 主要目录

```text
lib/                         Flutter 应用代码
lib/services/ffmpeg_bundle.dart   内置 ffmpeg/ffprobe 复制和自检
lib/services/video_probe_service.dart  视频检查逻辑
lib/services/video_convert_service.dart 视频转换逻辑
assets/bin/                  内置 ffmpeg/ffprobe
assets/videotrans_icon.png   App 图标源图
macos/                       macOS runner
windows/                     Windows runner
```

## 备注

本项目内置带 `libx264` 的 ffmpeg，适合内部使用。公开分发或商业分发前，需要确认 ffmpeg 及相关编码器的授权合规要求。
