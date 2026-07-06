import 'dart:convert';
import 'dart:io';

import '../models/video_job.dart';

class VideoProbeService {
  VideoProbeService({required this.ffprobe});

  final String ffprobe;
  final _atomRegExp = RegExp(
    r"type:'(?<type>\w+)'\s+parent:'(?<parent>\w+)'\s+sz:\s+(?<size>\d+)\s+(?<offset>\d+)",
  );

  Future<void> check(VideoJob job) async {
    job.status = JobStatus.checking;
    job.errorMessage = null;
    try {
      final atoms = await _getTopLevelAtoms(job.file.path);
      job.atoms = atoms;
      if (atoms.isEmpty) {
        job.moovStatus = MoovStatus.error;
        job.errorMessage = '未解析到 atom 信息，可能不是 MP4/MOV';
        job.status = JobStatus.failed;
        return;
      }

      final moovOffset = atoms
          .where((a) => a.type == 'moov')
          .map((a) => a.offset)
          .firstOrNull;
      final mdatOffset = atoms
          .where((a) => a.type == 'mdat')
          .map((a) => a.offset)
          .firstOrNull;
      if (moovOffset == null) {
        job.moovStatus = MoovStatus.noMoov;
      } else if (mdatOffset == null || moovOffset < mdatOffset) {
        job.moovStatus = MoovStatus.ok;
      } else {
        job.moovStatus = MoovStatus.bad;
      }

      job.videoBitrate = await _getVideoBitrate(job.file.path);
      final info = await _getVideoInfo(job.file.path);
      job.videoCodec = info.codec;
      job.videoProfile = info.profile;
      job.videoLevel = info.level;
      job.videoPixFmt = info.pixFmt;
      job.duration = info.duration ?? await _getFormatDuration(job.file.path);
      job.status =
          job.moovStatus == MoovStatus.error ||
              job.moovStatus == MoovStatus.noMoov
          ? JobStatus.failed
          : JobStatus.ready;
      if (job.moovStatus == MoovStatus.noMoov) {
        job.errorMessage = '未找到 moov atom，可能已损坏或为分片 MP4';
      }
    } catch (error) {
      job.moovStatus = MoovStatus.error;
      job.errorMessage = error.toString();
      job.status = JobStatus.failed;
    }
  }

  Future<List<AtomInfo>> _getTopLevelAtoms(String filePath) async {
    final result = await _runProbe(['-v', 'trace', '-i', filePath]);
    final stderr = result.stderr?.toString() ?? '';
    final atoms = <AtomInfo>[];
    for (final line in const LineSplitter().convert(stderr)) {
      final match = _atomRegExp.firstMatch(line);
      if (match == null || match.namedGroup('parent') != 'root') continue;
      atoms.add(
        AtomInfo(
          type: match.namedGroup('type')!,
          offset: int.parse(match.namedGroup('offset')!),
          size: int.parse(match.namedGroup('size')!),
        ),
      );
    }
    return atoms;
  }

  Future<int?> _getVideoBitrate(String filePath) async {
    final streamValue = await _probeText([
      '-select_streams',
      'v:0',
      '-show_entries',
      'stream=bit_rate',
      '-of',
      'csv=p=0',
      filePath,
    ]);
    final formatValue =
        streamValue ??
        await _probeText([
          '-show_entries',
          'format=bit_rate',
          '-of',
          'csv=p=0',
          filePath,
        ]);
    if (formatValue == null) return null;
    return int.tryParse(formatValue);
  }

  Future<String?> _probeText(List<String> args) async {
    final result = await _runProbe(['-v', 'error', ...args]);
    final value = (result.stdout?.toString() ?? '').trim();
    if (value.isEmpty || value == 'N/A') return null;
    return value;
  }

  Future<_VideoInfo> _getVideoInfo(String filePath) async {
    final result = await _runProbe([
      '-v',
      'error',
      '-select_streams',
      'v:0',
      '-show_entries',
      'stream=codec_name,profile,level,pix_fmt,duration',
      '-of',
      'json',
      filePath,
    ]);
    final output = result.stdout?.toString() ?? '{}';
    final data = jsonDecode(output) as Map<String, dynamic>;
    final streams = data['streams'];
    if (streams is! List || streams.isEmpty || streams.first is! Map) {
      return const _VideoInfo();
    }
    final stream = streams.first as Map<String, dynamic>;
    final durationSeconds = double.tryParse(
      stream['duration']?.toString() ?? '',
    );
    return _VideoInfo(
      codec: stream['codec_name']?.toString(),
      profile: stream['profile']?.toString(),
      level: int.tryParse(stream['level']?.toString() ?? ''),
      pixFmt: stream['pix_fmt']?.toString(),
      duration: durationSeconds == null
          ? null
          : Duration(milliseconds: (durationSeconds * 1000).round()),
    );
  }

  Future<Duration?> _getFormatDuration(String filePath) async {
    final result = await _runProbe([
      '-v',
      'error',
      '-show_entries',
      'format=duration',
      '-of',
      'csv=p=0',
      filePath,
    ]);
    final seconds = double.tryParse((result.stdout?.toString() ?? '').trim());
    if (seconds == null) return null;
    return Duration(milliseconds: (seconds * 1000).round());
  }

  Future<ProcessResult> _runProbe(List<String> args) async {
    try {
      final result = await Process.run(ffprobe, args);
      if (result.exitCode == 0) return result;
      final stderr = result.stderr?.toString().trim() ?? '';
      final stdout = result.stdout?.toString().trim() ?? '';
      final detail = stderr.isNotEmpty ? stderr : stdout;
      throw StateError(
        'ffprobe 失败(exit ${result.exitCode})：${detail.isEmpty ? args.join(' ') : detail}',
      );
    } on ProcessException catch (error) {
      throw StateError('无法执行内置 ffprobe：${error.message} (${error.executable})');
    }
  }
}

class _VideoInfo {
  const _VideoInfo({
    this.codec,
    this.profile,
    this.level,
    this.pixFmt,
    this.duration,
  });

  final String? codec;
  final String? profile;
  final int? level;
  final String? pixFmt;
  final Duration? duration;
}
