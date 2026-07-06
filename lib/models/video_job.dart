import 'dart:io';

import 'package:path/path.dart' as p;

const videoExts = {'.mp4', '.m4v', '.mov'};
const maxBitrateBps = 1200000;
const bitrateTolerance = 1.1;
const targetKbps = 1200;
const targetBitrate = '1200k';
const targetMaxrate = '1500k';
const targetBufsize = '2400k';
const x264Preset = 'medium';
const targetAudioBitrate = '128k';
const maxH264Level = 40;
const targetH264Level = '3.1';
const targetH264Profile = 'Main';
const targetPixFmt = 'yuv420p';
const targetFps = '30';
const targetX264Params = 'keyint=60:min-keyint=60:scenecut=0';

enum MoovStatus { ok, bad, noMoov, error, unchecked }

enum JobStatus {
  waiting,
  checking,
  ready,
  converting,
  done,
  skipped,
  stopped,
  failed,
}

class AtomInfo {
  const AtomInfo({
    required this.type,
    required this.offset,
    required this.size,
  });

  final String type;
  final int offset;
  final int size;
}

class VideoJob {
  VideoJob(this.file)
    : id = file.path,
      fileName = p.basename(file.path),
      sizeBytes = file.existsSync() ? file.lengthSync() : 0;

  final String id;
  final File file;
  final String fileName;
  final int sizeBytes;

  MoovStatus moovStatus = MoovStatus.unchecked;
  List<AtomInfo> atoms = [];
  int? videoBitrate;
  String? videoCodec;
  String? videoProfile;
  int? videoLevel;
  String? videoPixFmt;
  Duration? duration;
  JobStatus status = JobStatus.waiting;
  double progress = 0;
  String? outputPath;
  String? errorMessage;

  bool get needsFaststart => moovStatus == MoovStatus.bad;

  bool get needsBitrateDown {
    final bitrate = videoBitrate;
    return bitrate != null && bitrate > maxBitrateBps * bitrateTolerance;
  }

  bool get needsLevelDown {
    return videoCodec == 'h264' &&
        videoLevel != null &&
        videoLevel! >= maxH264Level;
  }

  bool get needsProfileMain {
    return videoCodec == 'h264' &&
        videoProfile != null &&
        videoProfile!.toLowerCase() != targetH264Profile.toLowerCase();
  }

  bool get needsPixFmtConvert {
    return videoCodec == 'h264' &&
        videoPixFmt != null &&
        videoPixFmt != targetPixFmt;
  }

  bool get needsMainConvert {
    return needsBitrateDown ||
        needsLevelDown ||
        needsProfileMain ||
        needsPixFmtConvert;
  }

  bool get needsFix => needsFaststart || needsMainConvert;

  bool get canConvert =>
      needsFix &&
      moovStatus != MoovStatus.error &&
      moovStatus != MoovStatus.noMoov;

  String get sizeText => formatSize(sizeBytes);

  String get bitrateText =>
      videoBitrate == null ? '未知' : '${videoBitrate! ~/ 1000} kbps';

  String get codecText {
    if (videoCodec == null) return '编码未知';
    if (videoCodec == 'h264') {
      final profile = videoProfile ?? 'Profile未知';
      final level = videoLevel == null
          ? '未知'
          : (videoLevel! / 10).toStringAsFixed(1);
      final pixFmt = videoPixFmt ?? 'pix_fmt未知';
      return 'H.264 $profile Level $level $pixFmt';
    }
    return videoCodec!;
  }

  String get issueText {
    if (moovStatus == MoovStatus.error) return '错误';
    if (moovStatus == MoovStatus.noMoov) return '无 moov';
    final issues = <String>[];
    if (needsFaststart) issues.add('faststart');
    if (needsBitrateDown) issues.add('降码率');
    if (needsProfileMain) issues.add('Profile Main');
    if (needsLevelDown) issues.add('Level 3.1');
    if (needsPixFmtConvert) issues.add(targetPixFmt);
    if (issues.isEmpty && moovStatus == MoovStatus.ok) return '正常';
    if (issues.isEmpty) return '未检查';
    return issues.join(' / ');
  }

  String get statusText {
    switch (status) {
      case JobStatus.waiting:
        return '等待检查';
      case JobStatus.checking:
        return '检查中';
      case JobStatus.ready:
        return needsFix ? '待转换' : '正常';
      case JobStatus.converting:
        return '转换中 ${(progress * 100).clamp(0, 100).toStringAsFixed(0)}%';
      case JobStatus.done:
        return '完成';
      case JobStatus.skipped:
        return '跳过';
      case JobStatus.stopped:
        return '已停止';
      case JobStatus.failed:
        return '失败';
    }
  }
}

bool isSupportedVideoPath(String path) =>
    videoExts.contains(p.extension(path).toLowerCase());

String formatSize(int bytes) {
  var size = bytes.toDouble();
  for (final unit in ['B', 'KB', 'MB', 'GB']) {
    if (size < 1024) return '${size.toStringAsFixed(1)}$unit';
    size /= 1024;
  }
  return '${size.toStringAsFixed(1)}TB';
}
