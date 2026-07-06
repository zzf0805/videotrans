import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'models/video_job.dart';
import 'services/ffmpeg_bundle.dart';
import 'services/video_convert_service.dart';
import 'services/video_probe_service.dart';

enum _PaletteMode { ocean, sunset }

class _Palette {
  const _Palette({
    required this.bgTop,
    required this.bgBottom,
    required this.panel,
    required this.panelSoft,
    required this.stroke,
    required this.primary,
    required this.accent,
    required this.text,
    required this.muted,
    required this.danger,
    required this.warning,
    required this.success,
  });

  final Color bgTop;
  final Color bgBottom;
  final Color panel;
  final Color panelSoft;
  final Color stroke;
  final Color primary;
  final Color accent;
  final Color text;
  final Color muted;
  final Color danger;
  final Color warning;
  final Color success;
}

const _oceanPalette = _Palette(
  bgTop: Color(0xff07111f),
  bgBottom: Color(0xff0b2238),
  panel: Color(0xff101d2e),
  panelSoft: Color(0xff162941),
  stroke: Color(0xff274466),
  primary: Color(0xff22a7ff),
  accent: Color(0xff7cf7d4),
  text: Color(0xffedf7ff),
  muted: Color(0xff9fb5c9),
  danger: Color(0xffff6b7a),
  warning: Color(0xffffc45c),
  success: Color(0xff5ee6a8),
);

const _sunsetPalette = _Palette(
  bgTop: Color(0xff1b1007),
  bgBottom: Color(0xff3a2108),
  panel: Color(0xff24170c),
  panelSoft: Color(0xff33210f),
  stroke: Color(0xff6a4518),
  primary: Color(0xffff9f1c),
  accent: Color(0xffffe066),
  text: Color(0xfffff7e8),
  muted: Color(0xffd7b98a),
  danger: Color(0xffff6b6b),
  warning: Color(0xffffc145),
  success: Color(0xff8ce99a),
);

_Palette _activePalette = _oceanPalette;

Color get _bgTop => _activePalette.bgTop;
Color get _bgBottom => _activePalette.bgBottom;
Color get _panel => _activePalette.panel;
Color get _panelSoft => _activePalette.panelSoft;
Color get _stroke => _activePalette.stroke;
Color get _primary => _activePalette.primary;
Color get _accent => _activePalette.accent;
Color get _mint => _activePalette.accent;
Color get _text => _activePalette.text;
Color get _muted => _activePalette.muted;
Color get _danger => _activePalette.danger;
Color get _warning => _activePalette.warning;
Color get _success => _activePalette.success;

void main() {
  runApp(const VideoTransApp());
}

class VideoTransApp extends StatelessWidget {
  const VideoTransApp({super.key, this.prepareBundle = true});

  final bool prepareBundle;

  @override
  Widget build(BuildContext context) {
    final palette = _activePalette;
    return MaterialApp(
      title: '视频标准化工具',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: palette.primary,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: palette.bgTop,
        useMaterial3: true,
        fontFamily: Platform.isMacOS ? 'PingFang SC' : null,
      ),
      home: HomePage(prepareBundle: prepareBundle),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.prepareBundle = true});

  final bool prepareBundle;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _jobs = <VideoJob>[];
  FfmpegExecutables? _executables;
  Directory? _outputDir;
  bool _dragging = false;
  bool _busy = false;
  bool _stopRequested = false;
  String? _bundleError;
  VideoConvertService? _converter;
  _PaletteMode _paletteMode = _PaletteMode.ocean;

  _Palette get _palette =>
      _paletteMode == _PaletteMode.ocean ? _oceanPalette : _sunsetPalette;

  String get _nextPaletteLabel =>
      _paletteMode == _PaletteMode.ocean ? '暖阳橙黄' : '深海蓝青';

  @override
  void initState() {
    super.initState();
    if (widget.prepareBundle) {
      _prepareBundle();
    }
  }

  Future<void> _prepareBundle() async {
    try {
      final executables = await FfmpegBundle().prepare();
      setState(() {
        _executables = executables;
        _bundleError = null;
      });
    } catch (error) {
      setState(() => _bundleError = error.toString());
    }
  }

  Future<void> _addPaths(Iterable<String> paths) async {
    final files = <File>[];
    for (final path in paths) {
      final type = FileSystemEntity.typeSync(path);
      if (type == FileSystemEntityType.directory) {
        files.addAll(_scanDirectory(Directory(path)));
      } else if (type == FileSystemEntityType.file &&
          isSupportedVideoPath(path)) {
        files.add(File(path));
      }
    }
    if (files.isEmpty) return;
    final existing = _jobs.map((job) => job.file.path).toSet();
    setState(() {
      for (final file in files) {
        if (existing.add(file.path)) _jobs.add(VideoJob(file));
      }
      _outputDir ??= Directory(
        p.join(p.dirname(_jobs.first.file.path), 'videotrans_output'),
      );
    });
  }

  List<File> _scanDirectory(Directory directory) {
    if (!directory.existsSync()) return [];
    return directory
        .listSync()
        .whereType<File>()
        .where((file) => isSupportedVideoPath(file.path))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
  }

  Future<void> _pickFiles() async {
    final files = await openFiles(
      acceptedTypeGroups: [
        const XTypeGroup(label: '视频', extensions: ['mp4', 'm4v', 'mov']),
      ],
    );
    await _addPaths(files.map((file) => file.path));
  }

  Future<void> _pickFolder() async {
    final path = await getDirectoryPath(confirmButtonText: '选择');
    if (path != null) await _addPaths([path]);
  }

  Future<void> _pickOutputDir() async {
    final path = await getDirectoryPath(confirmButtonText: '选择输出目录');
    if (path != null) setState(() => _outputDir = Directory(path));
  }

  Future<void> _checkAll() async {
    final executables = _executables;
    if (executables == null || _busy) return;
    setState(() => _busy = true);
    await _checkJobs(executables);
    setState(() => _busy = false);
  }

  Future<void> _checkJobs(FfmpegExecutables executables) async {
    final probe = VideoProbeService(ffprobe: executables.ffprobe);
    for (final job in _jobs) {
      setState(() {});
      await probe.check(job);
      setState(() {});
    }
  }

  Future<void> _convertAll() async {
    final executables = _executables;
    final outputDir = _outputDir;
    if (executables == null || outputDir == null || _busy) return;
    setState(() {
      _busy = true;
      _stopRequested = false;
    });

    if (_jobs.any((job) => job.moovStatus == MoovStatus.unchecked)) {
      await _checkJobs(executables);
    }

    final converter = VideoConvertService(ffmpeg: executables.ffmpeg);
    _converter = converter;
    for (final job in _jobs.where(
      (job) => job.canConvert && job.status != JobStatus.done,
    )) {
      if (_stopRequested) break;
      await converter.convert(
        job,
        outputDir,
        onProgress: (_) {
          if (mounted) setState(() {});
        },
      );
      setState(() {});
      if (_stopRequested) break;
    }
    _converter = null;
    setState(() {
      _busy = false;
      _stopRequested = false;
    });
  }

  void _stopConversion() {
    if (!_busy) return;
    setState(() => _stopRequested = true);
    _converter?.cancel();
  }

  Future<void> _openOutputDir() async {
    final dir = _outputDir;
    if (dir == null) return;
    if (!dir.existsSync()) dir.createSync(recursive: true);
    if (Platform.isMacOS) {
      await Process.run('open', [dir.path]);
    } else if (Platform.isWindows) {
      await Process.run('explorer', [dir.path]);
    }
  }

  void _clear() {
    if (_busy) return;
    setState(() => _jobs.clear());
  }

  void _showHelp() {
    _activePalette = _palette;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _panel,
        title: Text('使用说明', style: TextStyle(color: _text)),
        content: const Text(
          '1. 拖入视频，或点击“添加文件/添加文件夹”。\n'
          '2. 点击“检查全部”，查看哪些视频需要处理。\n'
          '3. 点击“一键全部转换”，处理后的视频会保存到输出目录。\n'
          '4. 原视频不会被覆盖，重名文件会自动加数字。\n'
          '5. 转换按队列一次处理 1 个视频；点击“停止转换”后，再点“一键全部转换”会从未完成的视频继续。\n'
          '6. 支持 MP4、M4V、MOV。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  void _togglePalette() {
    setState(() {
      _paletteMode = _paletteMode == _PaletteMode.ocean
          ? _PaletteMode.sunset
          : _PaletteMode.ocean;
      _activePalette = _palette;
    });
  }

  @override
  Widget build(BuildContext context) {
    final issueCount = _jobs.where((job) => job.needsFix).length;
    final encodeCount = _jobs.where((job) => job.needsMainConvert).length;
    final remuxCount = _jobs
        .where((job) => job.needsFix && !job.needsMainConvert)
        .length;
    _activePalette = _palette;
    return Scaffold(
      body: DropTarget(
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: (detail) {
          setState(() => _dragging = false);
          _addPaths(detail.files.map((file) => file.path));
        },
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_bgTop, _bgBottom],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(
                    bundleError: _bundleError,
                    outputDir: _outputDir?.path,
                    nextPaletteLabel: _nextPaletteLabel,
                    onTogglePalette: _togglePalette,
                    onShowHelp: _showHelp,
                    onPickOutput: _pickOutputDir,
                  ),
                  const SizedBox(height: 16),
                  _DropBox(dragging: _dragging),
                  const SizedBox(height: 14),
                  _ActionBar(
                    busy: _busy,
                    executablesReady: _executables != null,
                    onPickFiles: _pickFiles,
                    onPickFolder: _pickFolder,
                    onCheckAll: _checkAll,
                    onConvertAll: _convertAll,
                    onStop: _stopConversion,
                    onOpenOutput: _openOutputDir,
                    onClear: _clear,
                  ),
                  const SizedBox(height: 10),
                  _SummaryStrip(
                    total: _jobs.length,
                    issueCount: issueCount,
                    encodeCount: encodeCount,
                    remuxCount: remuxCount,
                  ),
                  const SizedBox(height: 14),
                  Expanded(child: _JobList(jobs: _jobs)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.bundleError,
    required this.outputDir,
    required this.nextPaletteLabel,
    required this.onTogglePalette,
    required this.onShowHelp,
    required this.onPickOutput,
  });

  final String? bundleError;
  final String? outputDir;
  final String nextPaletteLabel;
  final VoidCallback onTogglePalette;
  final VoidCallback onShowHelp;
  final VoidCallback onPickOutput;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.asset(
              'assets/videotrans_icon.png',
              width: 64,
              height: 64,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '在线视频标准化工具',
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                    color: _text,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '批量检查 faststart、码率和 H.264 兼容性，并输出到新文件夹',
                  style: TextStyle(color: _muted, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Text(
                  '输出目录：${outputDir ?? '添加视频后默认创建 videotrans_output，可手动选择'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _muted),
                ),
                if (bundleError != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    bundleError!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: _danger, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Row(
            children: [
              _GhostButton(
                icon: Icons.palette_outlined,
                label: nextPaletteLabel,
                onPressed: onTogglePalette,
              ),
              const SizedBox(width: 10),
              _GhostButton(
                icon: Icons.help_outline,
                label: '使用说明',
                onPressed: onShowHelp,
              ),
              const SizedBox(width: 10),
              _GhostButton(
                icon: Icons.drive_folder_upload,
                label: '选择输出目录',
                onPressed: onPickOutput,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DropBox extends StatelessWidget {
  const _DropBox({required this.dragging});

  final bool dragging;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: 122,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: dragging ? _accent : _stroke,
          width: dragging ? 2.2 : 1.2,
        ),
        gradient: LinearGradient(
          colors: dragging
              ? [
                  _primary.withValues(alpha: 0.24),
                  _accent.withValues(alpha: 0.12),
                ]
              : [
                  _panelSoft.withValues(alpha: 0.72),
                  _panel.withValues(alpha: 0.56),
                ],
        ),
        boxShadow: [
          if (dragging)
            BoxShadow(
              color: _accent.withValues(alpha: 0.25),
              blurRadius: 28,
              spreadRadius: 1,
            ),
        ],
      ),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_upload_outlined, color: _mint, size: 34),
            SizedBox(width: 14),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '拖入视频或文件夹',
                  style: TextStyle(
                    color: _text,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  '支持 MP4 / M4V / MOV，统一输出到新文件夹，不覆盖原文件',
                  style: TextStyle(color: _muted, fontSize: 13),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.busy,
    required this.executablesReady,
    required this.onPickFiles,
    required this.onPickFolder,
    required this.onCheckAll,
    required this.onConvertAll,
    required this.onStop,
    required this.onOpenOutput,
    required this.onClear,
  });

  final bool busy;
  final bool executablesReady;
  final VoidCallback onPickFiles;
  final VoidCallback onPickFolder;
  final VoidCallback onCheckAll;
  final VoidCallback onConvertAll;
  final VoidCallback onStop;
  final VoidCallback onOpenOutput;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _SolidButton(
            icon: Icons.video_file,
            label: '添加文件',
            onPressed: busy ? null : onPickFiles,
          ),
          const SizedBox(width: 10),
          _GhostButton(
            icon: Icons.folder_open,
            label: '添加文件夹',
            onPressed: busy ? null : onPickFolder,
          ),
          const SizedBox(width: 10),
          _GhostButton(
            icon: Icons.search,
            label: '检查全部',
            onPressed: busy || !executablesReady ? null : onCheckAll,
          ),
          const SizedBox(width: 10),
          _SolidButton(
            icon: Icons.play_arrow,
            label: '一键全部转换',
            onPressed: busy || !executablesReady ? null : onConvertAll,
          ),
          const SizedBox(width: 10),
          _DangerButton(
            icon: Icons.stop,
            label: '停止转换',
            onPressed: busy ? onStop : null,
          ),
          const SizedBox(width: 10),
          _GhostButton(
            icon: Icons.output,
            label: '打开输出目录',
            onPressed: onOpenOutput,
          ),
          const SizedBox(width: 10),
          _TextAction(
            icon: Icons.clear,
            label: '清空',
            onPressed: busy ? null : onClear,
          ),
        ],
      ),
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({
    required this.total,
    required this.issueCount,
    required this.encodeCount,
    required this.remuxCount,
  });

  final int total;
  final int issueCount;
  final int encodeCount;
  final int remuxCount;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _Metric(label: '总数', value: total.toString(), color: _text),
          _Metric(label: '需处理', value: issueCount.toString(), color: _warning),
          _Metric(label: '重编码', value: encodeCount.toString(), color: _primary),
          _Metric(label: '无损', value: remuxCount.toString(), color: _mint),
          Text('队列顺序转换，同时转换 1 个视频', style: TextStyle(color: _muted)),
        ],
      ),
    );
  }
}

class _JobList extends StatelessWidget {
  const _JobList({required this.jobs});

  final List<VideoJob> jobs;

  @override
  Widget build(BuildContext context) {
    if (jobs.isEmpty) {
      return _GlassPanel(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.video_library_outlined,
                color: _muted.withValues(alpha: 0.7),
                size: 54,
              ),
              const SizedBox(height: 12),
              Text(
                '还没有视频',
                style: TextStyle(
                  color: _text,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text('拖入文件，或点击“添加文件”开始。', style: TextStyle(color: _muted)),
            ],
          ),
        ),
      );
    }
    return Scrollbar(
      child: ListView.separated(
        itemCount: jobs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) => _JobCard(job: jobs[index]),
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job});

  final VideoJob job;

  @override
  Widget build(BuildContext context) {
    final outputName = job.outputPath == null
        ? '尚未生成'
        : p.basename(job.outputPath!);
    return _GlassPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: _primary.withValues(alpha: 0.28)),
                ),
                child: Icon(Icons.movie_creation_outlined, color: _primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _text,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${job.sizeText}  /  ${job.bitrateText}  /  ${job.codecText}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _StatusPill(job: job),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: _issueChips(job)),
          if (job.status == JobStatus.converting) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 8,
                value: job.progress <= 0 ? null : job.progress,
                color: _mint,
                backgroundColor: _stroke.withValues(alpha: 0.55),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.output, size: 15, color: _muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '输出：$outputName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
              ),
            ],
          ),
          if (job.errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              job.errorMessage!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _danger, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _issueChips(VideoJob job) {
    if (job.moovStatus == MoovStatus.error) return [_Chip('错误', _danger)];
    if (job.moovStatus == MoovStatus.noMoov) {
      return [_Chip('无 moov', _danger)];
    }
    final chips = <Widget>[];
    if (job.needsFaststart) chips.add(_Chip('faststart', _mint));
    if (job.needsBitrateDown) chips.add(_Chip('降码率', _warning));
    if (job.needsProfileMain) chips.add(_Chip('Profile Main', _primary));
    if (job.needsLevelDown) chips.add(_Chip('Level 3.1', _primary));
    if (job.needsPixFmtConvert) chips.add(_Chip(targetPixFmt, _primary));
    if (chips.isEmpty && job.moovStatus == MoovStatus.ok) {
      return [_Chip('正常', _success)];
    }
    if (chips.isEmpty) return [_Chip('未检查', _muted)];
    return chips;
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.job});

  final VideoJob job;

  @override
  Widget build(BuildContext context) {
    final color = switch (job.status) {
      JobStatus.waiting => _muted,
      JobStatus.checking => _primary,
      JobStatus.ready => job.needsFix ? _warning : _success,
      JobStatus.converting => _mint,
      JobStatus.done => _success,
      JobStatus.skipped => _muted,
      JobStatus.stopped => _warning,
      JobStatus.failed => _danger,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        job.statusText,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label $value',
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: _panel.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _stroke.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SolidButton extends StatelessWidget {
  const _SolidButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: _stroke,
        disabledForegroundColor: _muted,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  const _GhostButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: _text,
        disabledForegroundColor: _muted.withValues(alpha: 0.55),
        side: BorderSide(color: _stroke.withValues(alpha: 0.9)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class _DangerButton extends StatelessWidget {
  const _DangerButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: _danger.withValues(alpha: 0.18),
        foregroundColor: _danger,
        disabledBackgroundColor: _stroke.withValues(alpha: 0.35),
        disabledForegroundColor: _muted.withValues(alpha: 0.55),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class _TextAction extends StatelessWidget {
  const _TextAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: TextButton.styleFrom(foregroundColor: _muted),
    );
  }
}
