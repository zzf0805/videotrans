import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class FfmpegExecutables {
  const FfmpegExecutables({required this.ffmpeg, required this.ffprobe});

  final String ffmpeg;
  final String ffprobe;
}

class FfmpegBundle {
  Future<FfmpegExecutables> prepare() async {
    final platformDir = await _platformDir();
    final exeExt = Platform.isWindows ? '.exe' : '';
    final supportDir = await getApplicationSupportDirectory();
    final binDir = Directory(p.join(supportDir.path, 'bin', platformDir));
    if (!binDir.existsSync()) {
      binDir.createSync(recursive: true);
    }

    final ffmpeg = await _copyExecutable(
      assetPath: 'assets/bin/$platformDir/ffmpeg$exeExt',
      outputPath: p.join(binDir.path, 'ffmpeg$exeExt'),
    );
    final ffprobe = await _copyExecutable(
      assetPath: 'assets/bin/$platformDir/ffprobe$exeExt',
      outputPath: p.join(binDir.path, 'ffprobe$exeExt'),
    );

    if (!Platform.isWindows) {
      await _prepareMacExecutable(ffmpeg);
      await _prepareMacExecutable(ffprobe);
    }
    await _verifyExecutable(ffmpeg, 'ffmpeg');
    await _verifyExecutable(ffprobe, 'ffprobe');
    return FfmpegExecutables(ffmpeg: ffmpeg, ffprobe: ffprobe);
  }

  Future<String> _platformDir() async {
    if (Platform.isMacOS) {
      final arch = await _normalizedArch();
      if (arch == 'arm64') return 'macos-arm64';
      throw UnsupportedError('第一版只支持 Apple Silicon Mac，不支持当前架构：$arch');
    }
    if (Platform.isWindows) {
      final arch = await _normalizedArch();
      if (arch == 'x64' || arch == 'amd64') return 'windows-x64';
      throw UnsupportedError('第一版只支持 Windows x64，不支持当前架构：$arch');
    }
    throw UnsupportedError('第一版只支持 macOS arm64 和 Windows x64');
  }

  Future<String> _normalizedArch() async {
    if (Platform.isMacOS) {
      final result = await Process.run('/usr/bin/uname', ['-m']);
      final arch = result.stdout.toString().trim().toLowerCase();
      if (arch.isNotEmpty) return arch;
    }
    final executable = Platform.resolvedExecutable.toLowerCase();
    if (Platform.isMacOS) {
      if (executable.contains('arm64')) return 'arm64';
      final arch = Platform.environment['PROCESSOR_ARCHITECTURE']
          ?.toLowerCase();
      if (arch != null && arch.contains('arm')) return 'arm64';
    }
    if (Platform.isWindows) {
      final arch = Platform.environment['PROCESSOR_ARCHITECTURE']
          ?.toLowerCase();
      if (arch == 'amd64' || arch == 'x64') return 'x64';
    }
    final version = Platform.version.toLowerCase();
    if (version.contains('arm64')) return 'arm64';
    if (version.contains('x64')) return 'x64';
    return version;
  }

  Future<void> _prepareMacExecutable(String path) async {
    await Process.run('chmod', ['+x', path]);
    await Process.run('xattr', ['-d', 'com.apple.quarantine', path]);
    await Process.run('/usr/bin/codesign', ['-f', '-s', '-', path]);
  }

  Future<void> _verifyExecutable(String path, String name) async {
    try {
      final result = await Process.run(path, ['-version']);
      if (result.exitCode == 0) return;
      final stderr = result.stderr?.toString().trim() ?? '';
      final stdout = result.stdout?.toString().trim() ?? '';
      final detail = stderr.isNotEmpty ? stderr : stdout;
      throw StateError(
        '内置 $name 无法运行(exit ${result.exitCode})：${detail.isEmpty ? path : detail}',
      );
    } on ProcessException catch (error) {
      throw StateError('内置 $name 无法运行：${error.message} (${error.executable})');
    }
  }

  Future<String> _copyExecutable({
    required String assetPath,
    required String outputPath,
  }) async {
    try {
      final data = await rootBundle.load(assetPath);
      final file = File(outputPath);
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      return file.path;
    } on FlutterError catch (error) {
      throw StateError('内置转码组件缺失：$assetPath\n$error');
    }
  }
}
