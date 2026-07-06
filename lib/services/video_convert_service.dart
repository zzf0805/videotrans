import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/video_job.dart';

class VideoConvertService {
  VideoConvertService({required this.ffmpeg});

  final String ffmpeg;
  Process? _currentProcess;
  bool _cancelRequested = false;

  void cancel() {
    _cancelRequested = true;
    _currentProcess?.kill();
  }

  Future<void> convert(
    VideoJob job,
    Directory outputDir, {
    void Function(double progress)? onProgress,
  }) async {
    _cancelRequested = false;
    if (!job.canConvert) {
      job.status = JobStatus.skipped;
      return;
    }
    if (!outputDir.existsSync()) outputDir.createSync(recursive: true);

    final outputPath = _uniqueOutputPath(job, outputDir);
    job.outputPath = outputPath;
    job.status = JobStatus.converting;
    job.progress = 0;
    job.errorMessage = null;

    final args = _buildArgs(job, outputPath);
    final process = await Process.start(ffmpeg, args);
    _currentProcess = process;
    final stderr = StringBuffer();

    final stdoutDone = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final progress = _parseProgress(line, job.duration);
          if (progress != null) {
            job.progress = progress;
            onProgress?.call(progress);
          }
        })
        .asFuture<void>();

    final stderrDone = process.stderr
        .transform(utf8.decoder)
        .listen(stderr.write)
        .asFuture<void>();
    final exitCode = await process.exitCode;
    await Future.wait([stdoutDone, stderrDone]);
    _currentProcess = null;

    if (_cancelRequested) {
      final output = File(outputPath);
      if (output.existsSync()) {
        try {
          output.deleteSync();
        } on FileSystemException {
          // Best effort cleanup; a later conversion will choose a unique name.
        }
      }
      job.status = JobStatus.stopped;
      job.progress = 0;
      job.outputPath = null;
      job.errorMessage = null;
      return;
    }

    if (exitCode != 0) {
      job.status = JobStatus.failed;
      final text = stderr.toString();
      job.errorMessage = text.length > 700
          ? text.substring(text.length - 700)
          : text;
      return;
    }
    job.progress = 1;
    onProgress?.call(1);
    job.status = JobStatus.done;
  }

  List<String> _buildArgs(VideoJob job, String outputPath) {
    final commonProgress = ['-progress', 'pipe:1', '-nostats'];
    if (job.needsMainConvert) {
      return [
        '-y',
        '-i',
        job.file.path,
        '-c:v',
        'libx264',
        '-profile:v',
        'main',
        '-level:v',
        targetH264Level,
        '-pix_fmt',
        targetPixFmt,
        '-r',
        targetFps,
        '-x264-params',
        targetX264Params,
        '-b:v',
        targetBitrate,
        '-maxrate',
        targetMaxrate,
        '-bufsize',
        targetBufsize,
        '-preset',
        x264Preset,
        '-colorspace',
        'bt709',
        '-color_primaries',
        'bt709',
        '-color_trc',
        'bt709',
        '-c:a',
        'aac',
        '-b:a',
        targetAudioBitrate,
        '-movflags',
        '+faststart',
        '-brand',
        'mp42',
        ...commonProgress,
        outputPath,
      ];
    }
    return [
      '-y',
      '-i',
      job.file.path,
      '-c',
      'copy',
      '-movflags',
      '+faststart',
      '-brand',
      'mp42',
      ...commonProgress,
      outputPath,
    ];
  }

  double? _parseProgress(String line, Duration? duration) {
    if (line == 'progress=end') return 1;
    final totalMs = duration?.inMilliseconds;
    if (totalMs == null || totalMs <= 0) return null;

    final separatorIndex = line.indexOf('=');
    if (separatorIndex == -1) return null;
    final key = line.substring(0, separatorIndex);
    final value = line.substring(separatorIndex + 1);

    final outMs = switch (key) {
      'out_time_us' => _parseNumericTime(value, totalMs, microseconds: true),
      'out_time_ms' => _parseNumericTime(value, totalMs),
      'out_time' => _parseClockTime(value),
      _ => null,
    };
    if (outMs == null) return null;
    return (outMs / totalMs).clamp(0, 0.99).toDouble();
  }

  double? _parseNumericTime(
    String value,
    int totalMs, {
    bool microseconds = false,
  }) {
    final raw = int.tryParse(value);
    if (raw == null) return null;
    if (microseconds || raw > totalMs * 100) return raw / 1000;
    return raw.toDouble();
  }

  double? _parseClockTime(String value) {
    final parts = value.split(':');
    if (parts.length != 3) return null;
    final hours = int.tryParse(parts[0]);
    final minutes = int.tryParse(parts[1]);
    final seconds = double.tryParse(parts[2]);
    if (hours == null || minutes == null || seconds == null) return null;
    return ((hours * 3600 + minutes * 60 + seconds) * 1000).toDouble();
  }

  String _uniqueOutputPath(VideoJob job, Directory outputDir) {
    final suffix = '_trans';
    final extension = p.extension(job.file.path);
    final baseName = p.basenameWithoutExtension(job.file.path);
    var candidate = p.join(outputDir.path, '$baseName$suffix$extension');
    var index = 1;
    while (File(candidate).existsSync()) {
      candidate = p.join(outputDir.path, '$baseName${suffix}_$index$extension');
      index += 1;
    }
    return candidate;
  }
}
