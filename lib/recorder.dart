import 'dart:async';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'recording_controls_panel.dart';
import 'target_app_input.dart';
import 'trace_utils.dart';
import 'l10n/app_localizations.dart';

/// Describes an adb shell command to run in the background during recording.
/// [shellCommand] is executed as `adb shell <shellCommand>`.
/// [outputFileName] is an optional local filename to save output into (inside Traces/).
class BackgroundCommand {
  final String shellCommand;
  final String? outputFileName;
  const BackgroundCommand({
    required this.shellCommand,
    this.outputFileName,
  });
}

class RecordingMode {
  final String label;
  final IconData icon;
  final String description;
  final List<String> atraceCategories;
  final List<String> ftraceEvents;

  /// Optional long-running adb command kept alive for the duration of recording.
  final BackgroundCommand? backgroundCommand;
  final Future<void> Function(String? deviceId)? onStart;
  final Future<void> Function(String? deviceId)? onStop;

  const RecordingMode({
    required this.label,
    required this.icon,
    this.description = '',
    this.atraceCategories = const [],
    this.ftraceEvents = const [],
    this.backgroundCommand,
    this.onStart,
    this.onStop,
  });
}

class RecorderScreen extends StatefulWidget {
  const RecorderScreen({super.key});

  @override
  State<RecorderScreen> createState() => _RecorderScreenState();
}

class _RecorderScreenState extends State<RecorderScreen> {
  double _durationMs = 10000;
  bool _autoBufferSize = true;
  bool _isButtonLocked = false;

  // Duration steps for the slider
  final List<int> _durationSteps = [
    10000,
    15000,
    30000,
    60000,
    180000,
    300000,
    600000,
    900000,
    1800000,
    3600000
  ];

  final List<RecordingMode> _recordingModes = [
    RecordingMode(
      label: 'Performance',
      icon: Icons.speed,
      description: 'Standard gfx + window-manager hooks',
      atraceCategories: ['gfx', 'input', 'view', 'wm', 'am'],
    ),
    // RecordingMode(
    //   label: 'Camera Tuning',
    //   icon: Icons.camera_alt,
    //   atraceCategories: [
    //     'camera',
    //     'hal',
    //     'video',
    //     'ion',
    //     'gfx',
    //     'sched',
    //     'freq',
    //     'idle'
    //   ],
    // ),
    RecordingMode(
      label: 'Graphic Memory',
      icon: Icons.videogame_asset,
      atraceCategories: ['gfx', 'sched', 'freq', 'idle'],
      // Example onStart/onStop Hooks for extra logging config or ADB action
    ),
    RecordingMode(
      label: 'Kernel Events',
      icon: Icons.developer_board,
      atraceCategories: [
        'sched',
        'freq',
        'idle',
        'irq',
        'workq',
        'disk',
        'sync'
      ],
    ),
    RecordingMode(
      label: 'Logcat',
      icon: Icons.terminal,
      description: 'Collect logcat output during recording',
      backgroundCommand: BackgroundCommand(
        shellCommand: 'logcat -v threadtime',
        outputFileName: 'logcat.txt',
      ),
    ),
    // RecordingMode(
    //   label: 'Show Touches (Example)',
    //   icon: Icons.touch_app,
    //   description: 'ADB: enable touch dots during recording',
    //   onStart: (deviceId) async {
    //     final deviceArgs = deviceId != null ? ['-s', deviceId] : [];
    //     await Process.run('adb', [
    //       ...deviceArgs, 'shell', 'settings', 'put', 'system', 'show_touches', '1'
    //     ]);
    //   },
    //   onStop: (deviceId) async {
    //     final deviceArgs = deviceId != null ? ['-s', deviceId] : [];
    //     await Process.run('adb', [
    //       ...deviceArgs, 'shell', 'settings', 'put', 'system', 'show_touches', '0'
    //     ]);
    //   },
    // ),
  ];

  String _formatDuration(int ms) {
    final duration = Duration(milliseconds: ms);
    final mInt = duration.inMinutes;
    final m = mInt.toString().padLeft(2, '0');
    final s = duration.inSeconds.remainder(60).toString().padLeft(2, '0');

    return (mInt > 0) ? '$m:$s\tm:s' : '$s\tsec';
  }

  // Input Controllers
  final _atraceController = TextEditingController();
  final _ftraceController = TextEditingController();
  final _appNameController = TextEditingController();
  final _outputFileController = TextEditingController();
  final _bufferSizeController = TextEditingController();
  bool _autoGenerateFilename = true;

  // ADB Devices
  List<String> _adbDevices = [];
  String? _selectedDevice;

  Future<void> _refreshAdbDevices() async {
    await TraceUtils.refreshAdbDevices(
      currentDevice: _selectedDevice,
      onSuccess: (devices, selectedDevice) {
        if (mounted) {
          setState(() {
            _adbDevices = devices;
            _selectedDevice = selectedDevice;
          });
        }
      },
      onError: (error) {
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          _updateStatus(l10n.errorGettingDevices(error));
        }
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _generateNewFilename();
    _updateBufferSize();
    _refreshAdbDevices();

    _modesScrollController.addListener(_updateScrollGradient);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScrollGradient();
    });

    // Listen to category text changes to update presets
    _atraceController.addListener(() {
      if (mounted) setState(() {});
    });
    _ftraceController.addListener(() {
      if (mounted) setState(() {});
    });
    _appNameController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  void _generateNewFilename() {
    TraceUtils.generateNewFilename(
      prefix: '',
      controller: _outputFileController,
    );
  }

  void _updateBufferSize() {
    if (_autoBufferSize) {
      // Stepped buffer size based on duration
      // 0~15s → 64MB, 30s → 128MB, 60~90s → 256MB,
      // 3~5min → 512MB, 10~15min → 1024MB, 30min → 2048MB, 60min → 4096MB
      final durationSec = _durationMs ~/ 1000;
      int sizeMb;
      if (durationSec <= 15) {
        sizeMb = 64;
      } else if (durationSec <= 30) {
        sizeMb = 128;
      } else if (durationSec <= 90) {
        sizeMb = 256;
      } else if (durationSec <= 300) {
        sizeMb = 512;
      } else if (durationSec <= 900) {
        sizeMb = 1024;
      } else if (durationSec <= 1800) {
        sizeMb = 2048;
      } else {
        sizeMb = 4096;
      }
      // Clamp to user-allowed range
      sizeMb = sizeMb.clamp(16, 4096);
      _bufferSizeController.text = sizeMb.toString();
    }
  }

  // Selected Modes
  final Set<String> _selectedModeLabels = {'Performance'};

  // Toggle Mode
  void _toggleMode(String label, bool selected) {
    setState(() {
      if (selected) {
        _selectedModeLabels.add(label);
      } else {
        _selectedModeLabels.remove(label);
      }
    });
  }

  // Check if mode is selected
  bool _isModeSelected(String label) {
    return _selectedModeLabels.contains(label);
  }

  // Default ftrace events always included
  static const List<String> _defaultFtraceEvents = [
    'sched/sched_switch',
    'power/suspend_resume',
    'ftrace/print',
  ];

  /// Parse user input from a given controller
  List<String> _getUserTokens(TextEditingController controller) {
    return controller.text
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// All atrace categories
  Set<String> _getAtraceCategories() {
    final fromModes = <String>{};
    for (final mode in _recordingModes) {
      if (_selectedModeLabels.contains(mode.label)) {
        fromModes.addAll(mode.atraceCategories);
      }
    }
    final fromUser = _getUserTokens(_atraceController).toSet();
    return {...fromModes, ...fromUser};
  }

  /// All ftrace events
  Set<String> _getFtraceEvents() {
    final fromUser = _getUserTokens(_ftraceController).toSet();
    return {..._defaultFtraceEvents, ...fromUser};
  }

  /// All atrace apps from _appNameController (space-separated)
  Set<String> _getAtraceApps() {
    return _appNameController.text
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toSet();
  }

  // Process State
  bool _isRecording = false;
  bool _userStopped = false;
  Process? _recordingProcess;
  HttpServer? _server;
  Timer? _timer;
  int _elapsedMs = 0;

  /// Background processes spawned by selected RecordingMode.backgroundCommand
  final List<Process> _bgProcesses = [];

  final ScrollController _modesScrollController = ScrollController();
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  void _updateScrollGradient() {
    if (!_modesScrollController.hasClients) return;
    final pos = _modesScrollController.position;
    final canLeft = pos.pixels > 0;
    // maxScrollExtent could be 0 if items do not overflow
    final canRight =
        pos.pixels < pos.maxScrollExtent && pos.maxScrollExtent > 0;
    if (_canScrollLeft != canLeft || _canScrollRight != canRight) {
      if (mounted) {
        setState(() {
          _canScrollLeft = canLeft;
          _canScrollRight = canRight;
        });
      }
    }
  }

  void _lockButton() {
    setState(() {
      _isButtonLocked = true;
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _isButtonLocked = false;
        });
      }
    });
  }

  // Update Status Message
  void _updateStatus(String message,
      {Duration duration = const Duration(seconds: 2)}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: duration),
    );
  }

  // Config Generator
  String _generateConfig() {
    final duration = _durationMs.toInt();
    int bufferSizeKb = 32 * 1024;
    try {
      bufferSizeKb = int.parse(_bufferSizeController.text) * 1024;
    } catch (_) {}
    final atraceCategories = _getAtraceCategories().toList();
    final ftraceEvents = _getFtraceEvents().toList();
    final atraceApps = _getAtraceApps().toList();

    // Build ftrace_events lines
    String ftraceLines =
        ftraceEvents.map((e) => '            ftrace_events: "$e"').join('\n');

    // Build atrace_categories lines
    String atraceLines = atraceCategories
        .map((c) => '            atrace_categories: "$c"')
        .join('\n');

    // Build atrace_apps lines
    if (atraceApps.isNotEmpty) {
      final appsLines =
          atraceApps.map((a) => '            atrace_apps: "$a"').join('\n');
      atraceLines += '\n$appsLines';
    }

    return '''
buffers: {
    size_kb: $bufferSizeKb
    fill_policy: RING_BUFFER
}
duration_ms: $duration

data_sources: {
    config {
        name: "linux.ftrace"
        ftrace_config {
$ftraceLines
$atraceLines
        }
    }
}
data_sources: {
    config {
        name: "android.packages_list"
    }
}
''';
  }

  // --- Background Command Helpers ---

  /// Spawns all background commands for selected modes.
  Future<void> _startBackgroundCommands() async {
    final tracesDir = Directory('${Directory.current.path}\\Traces');
    if (!await tracesDir.exists()) {
      await tracesDir.create(recursive: true);
    }
    final deviceArgs =
        _selectedDevice != null ? ['-s', _selectedDevice!] : <String>[];

    for (final mode in _recordingModes) {
      if (!_selectedModeLabels.contains(mode.label)) continue;
      final cmd = mode.backgroundCommand;
      if (cmd == null) continue;

      IOSink? sink;
      if (cmd.outputFileName != null) {
        // Derive a unique filename: prepend trace basename
        final base = _outputFileController.text.replaceAll('.pftrace', '');
        final outPath = '${tracesDir.path}\\${base}_${cmd.outputFileName}';
        final outFile = File(outPath);
        sink = outFile.openWrite();
      }

      try {
        final proc = await Process.start(
          'adb',
          [...deviceArgs, 'shell', cmd.shellCommand],
          runInShell: false,
        );

        if (sink != null) {
          // Pipe stdout/stderr → file
          proc.stdout.listen((data) => sink!.add(data));
          proc.stderr.listen((data) => sink!.add(data));
          proc.exitCode.then((_) => sink!.close());
        } else {
          // No log file needed, drain streams to prevent deadlock
          proc.stdout.drain();
          proc.stderr.drain();
        }

        _bgProcesses.add(proc);
      } catch (e) {
        await sink?.close();
        _updateStatus('Warning: could not start background command: $e');
      }
    }
  }

  /// Kills all background processes.
  Future<void> _stopBackgroundCommands() async {
    for (final proc in _bgProcesses) {
      proc.kill();
    }
    _bgProcesses.clear();
  }

  // Start Recording
  Future<void> _startRecording() async {
    if (_isRecording) return;

    final l10n = AppLocalizations.of(context)!;
    // Validate ftrace inputs
    final ftraceTokens = _getUserTokens(_ftraceController);
    for (final token in ftraceTokens) {
      if (!token.contains('/')) {
        _updateStatus(l10n.ftraceFormatError(token));
        return;
      }
    }

    _lockButton();
    setState(() {
      _isRecording = true;
      _userStopped = false;
      if (_autoGenerateFilename) {
        _generateNewFilename();
      }
    });
    _updateStatus(l10n.startingPerfetto, duration: Duration(seconds: 1));

    final config = _generateConfig();
    final outputFile = _outputFileController.text;

    final deviceArgs = _selectedDevice != null ? ['-s', _selectedDevice!] : [];
    try {
      _recordingProcess = await Process.start(
        'adb',
        [
          ...deviceArgs,
          'shell',
          'perfetto',
          '-c',
          '-',
          '--txt',
          '-o',
          '"/data/misc/perfetto-traces/$outputFile"'
        ],
      );

      // Write config to stdin
      _recordingProcess!.stdin.write(config);
      await _recordingProcess!.stdin.flush();
      await _recordingProcess!.stdin.close();

      _updateStatus(l10n.recordingInProgress);

      // Start background commands (logcat, etc.)
      await _startBackgroundCommands();

      // Start Timer
      _elapsedMs = 0;
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(milliseconds: 100), (t) {
        setState(() {
          _elapsedMs += 100;
          if (_elapsedMs >= _durationMs) _elapsedMs = _durationMs.toInt();
        });
      });

      // Wait for process to complete
      final exitCode = await _recordingProcess!.exitCode;

      if (exitCode == 0 || _userStopped) {
        _updateStatus(l10n.recordingFinishedPulling);
        await _pullTraceFile(outputFile);
      } else {
        _updateStatus(l10n.perfettoError(exitCode.toString()));
      }
    } catch (e) {
      _updateStatus(l10n.errorStartingProcess(e.toString()));
    } finally {
      await _stopBackgroundCommands();
      if (mounted) {
        setState(() {
          _isRecording = false;
          _recordingProcess = null;
          _timer?.cancel();
        });
      }
    }
  }

  // Manual Stop Recording
  Future<void> _stopRecording() async {
    _timer?.cancel();
    _lockButton();
    await _stopBackgroundCommands();
    if (_recordingProcess != null) {
      _userStopped = true;
      if (!mounted) return;
      _updateStatus(AppLocalizations.of(context)!.stoppingManually,
          duration: const Duration(seconds: 1));
      await TraceUtils.stopPerfetto(_selectedDevice);
    }
  }

  // Pull Trace File from Device
  Future<void> _pullTraceFile(String traceName) async {
    await TraceUtils.pullTraceFile(
      context: context,
      traceName: traceName,
      selectedDevice: _selectedDevice,
      updateStatus: _updateStatus,
    );
  }

  Future<void> _openTraceInBrowser() async {
    final newServer = await TraceUtils.openTraceInBrowser(
      context: context,
      fileName: _outputFileController.text,
      existingServer: _server,
      updateStatus: _updateStatus,
    );
    if (newServer != null) {
      _server = newServer;
    }
  }

  // --- Categories Dialog ---
  void _showCategoriesDialog(BuildContext context) {
    final atraceCategories = _getAtraceCategories();
    final ftraceEvents = _getFtraceEvents();
    final atraceApps = _getAtraceApps();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        title: Row(
          children: [
            Icon(Icons.category,
                size: 20, color: Theme.of(ctx).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Activated Configs',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => Navigator.of(ctx).pop(),
              tooltip: 'Close',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: MediaQuery.of(ctx).size.width * 0.8,
            maxHeight: MediaQuery.of(ctx).size.height * 0.8,
          ),
          child: SizedBox(
            width: 425,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Atrace section
                  Text('atraces (${atraceCategories.length})',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(ctx).colorScheme.primary)),
                  const SizedBox(height: 6),
                  if (atraceCategories.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: atraceCategories
                          .map((tag) => Chip(
                                label: Text(tag,
                                    style: const TextStyle(fontSize: 12)),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ))
                          .toList(),
                    )
                  else
                    Text('—',
                        style: TextStyle(
                            color: Theme.of(ctx).colorScheme.outline)),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                  // Ftrace section
                  Text('ftraces (${ftraceEvents.length})',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(ctx).colorScheme.primary)),
                  const SizedBox(height: 6),
                  if (ftraceEvents.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: ftraceEvents
                          .map((tag) => Chip(
                                label: Text(tag,
                                    style: const TextStyle(fontSize: 12)),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ))
                          .toList(),
                    )
                  else
                    Text('—',
                        style: TextStyle(
                            color: Theme.of(ctx).colorScheme.outline)),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                  // Atrace Apps section
                  Text('atrace_apps (${atraceApps.length})',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(ctx).colorScheme.tertiary)),
                  const SizedBox(height: 6),
                  if (atraceApps.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: atraceApps
                          .map((tag) => Chip(
                                label: Text(tag,
                                    style: const TextStyle(fontSize: 12)),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ))
                          .toList(),
                    )
                  else
                    Text('—',
                        style: TextStyle(
                            color: Theme.of(ctx).colorScheme.outline)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _server?.close(force: true);
    _atraceController.dispose();
    _ftraceController.dispose();
    _appNameController.dispose();
    _outputFileController.dispose();
    _modesScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        forceMaterialTransparency: true,
        title: const Text('Perfetto UI Recorder'),
        actions: AdbDeviceSelector.asActions(
          devices: _adbDevices,
          selectedDevice: _selectedDevice,
          onChanged: (v) => setState(() => _selectedDevice = v),
          onRefresh: _refreshAdbDevices,
        ),
      ),
      body: Column(
        children: [
          // Top Section: Shared Recording Controls
          RecordingControlsPanel(
            elapsedMs: _elapsedMs,
            durationMs: _durationMs,
            isRecording: _isRecording,
            isButtonLocked: _isButtonLocked,
            durationSteps: _durationSteps,
            onDurationChanged: (v) => setState(() {
              _durationMs = v;
              _updateBufferSize();
            }),
            outputFileController: _outputFileController,
            autoGenerateFilename: _autoGenerateFilename,
            onToggleAutoFilename: () =>
                setState(() => _autoGenerateFilename = !_autoGenerateFilename),
            bufferSizeController: _bufferSizeController,
            autoBufferSize: _autoBufferSize,
            onToggleAutoBuffer: () => setState(() {
              _autoBufferSize = !_autoBufferSize;
              if (_autoBufferSize) _updateBufferSize();
            }),
            onStart: _startRecording,
            onStop: _stopRecording,
            onOpenExplorer: () async {
              final tracesDir = Directory('${Directory.current.path}\\Traces');
              final filePath =
                  '${tracesDir.path}\\${_outputFileController.text}';
              await openExplorer(filePath, tracesDir);
            },
            onOpenPerfetto: _openTraceInBrowser,
            sliderLabel: _formatDuration,
          ),

          const Divider(height: 1),

          // Bottom Section: Settings (Scrollable)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Recording Modes
                  _buildSectionTitle('Recording Modes'),
                  Theme(
                    data: Theme.of(context).copyWith(
                      splashFactory: NoSplash.splashFactory,
                      highlightColor: Colors.transparent,
                    ),
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(
                        dragDevices: {
                          PointerDeviceKind.touch,
                          PointerDeviceKind.mouse,
                        },
                      ),
                      child: Stack(
                        children: [
                          SingleChildScrollView(
                            controller: _modesScrollController,
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: _recordingModes.map((m) {
                                final label = m.label;
                                final isSelected = _isModeSelected(label);
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: FilterChip(
                                    showCheckmark: false,
                                    avatar: Icon(m.icon, size: 16),
                                    label: Text(label),
                                    tooltip: m.description.isNotEmpty
                                        ? m.description
                                        : null,
                                    selected: isSelected,
                                    onSelected: (v) => _toggleMode(label, v),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                          if (_canScrollLeft)
                            Positioned(
                              left: 0,
                              top: 0,
                              bottom: 0,
                              child: IgnorePointer(
                                child: Container(
                                  width: 40,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                      colors: [
                                        Theme.of(context).colorScheme.surface,
                                        Theme.of(context)
                                            .colorScheme
                                            .surface
                                            .withAlpha(0),
                                      ],
                                    ),
                                  ),
                                  alignment: Alignment.centerLeft,
                                  child: Icon(Icons.chevron_left,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface),
                                ),
                              ),
                            ),
                          if (_canScrollRight)
                            Positioned(
                              right: 0,
                              top: 0,
                              bottom: 0,
                              child: IgnorePointer(
                                child: Container(
                                  width: 40,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.centerRight,
                                      end: Alignment.centerLeft,
                                      colors: [
                                        Theme.of(context).colorScheme.surface,
                                        Theme.of(context)
                                            .colorScheme
                                            .surface
                                            .withAlpha(0),
                                      ],
                                    ),
                                  ),
                                  alignment: Alignment.centerRight,
                                  child: Icon(Icons.chevron_right,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // App Name Input
                  TargetAppInput(
                    controller: _appNameController,
                    labelText: "Target APP Names",
                    hintText: "e.g. com.android.launcher3, surfaceflinger",
                    prefixIcon: Icons.apps,
                    selectedDevice: _selectedDevice,
                    onMessage: _updateStatus,
                  ),
                  const Spacer(),

                  // Atrace Input
                  TextField(
                    controller: _atraceController,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: "Atrace categories",
                      hintText: "e.g. memory gfx input am pm",
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.category),
                      isDense: true,
                    ),
                  ),
                  const Spacer(),

                  // Ftrace Input
                  TextField(
                    controller: _ftraceController,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: "Ftrace events",
                      hintText: "e.g. sched/sched_switch irq/*",
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.category_outlined),
                      isDense: true,
                    ),
                  ),
                  const Spacer(),

                  // Active Categories Badge + View Button
                  InkWell(
                    onTap: () => _showCategoriesDialog(context),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color:
                            Theme.of(context).colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: Theme.of(context).dividerColor),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 8),
                          Text(
                            'Activated configs: ',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'atraces: ${_getAtraceCategories().length}',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color:
                                      Theme.of(context).colorScheme.onPrimary),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .secondaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'ftraces: ${_getFtraceEvents().length}',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSecondaryContainer),
                            ),
                          ),
                          if (_getAtraceApps().isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .tertiaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'apps: ${_getAtraceApps().length}',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onTertiaryContainer),
                              ),
                            ),
                          ],
                          const Spacer(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Text(
        title,
        style: const TextStyle(
            color: Colors.grey, fontSize: 14, fontWeight: FontWeight.bold),
      ),
    );
  }
}
