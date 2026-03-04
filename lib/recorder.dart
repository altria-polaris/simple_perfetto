import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'l10n/app_localizations.dart';

class RecordingMode {
  final String label;
  final IconData icon;
  final String description;
  final List<String> atraceCategories;
  final List<String> ftraceEvents;
  final Future<void> Function(String? deviceId)? onStart;
  final Future<void> Function(String? deviceId)? onStop;

  const RecordingMode({
    required this.label,
    required this.icon,
    this.description = '',
    this.atraceCategories = const [],
    this.ftraceEvents = const [],
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
  final TextEditingController _bufferSizeController = TextEditingController();
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
    RecordingMode(
      label: 'Camera Tuning',
      icon: Icons.camera_alt,
      atraceCategories: [
        'camera',
        'hal',
        'video',
        'ion',
        'gfx',
        'sched',
        'freq',
        'idle'
      ],
    ),
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
      label: 'Show Touches (Example)',
      icon: Icons.touch_app,
      description: 'ADB: enable touch dots during recording',
      onStart: (deviceId) async {
        final deviceArgs = deviceId != null ? ['-s', deviceId] : [];
        await Process.run('adb', [
          ...deviceArgs,
          'shell',
          'settings',
          'put',
          'system',
          'show_touches',
          '1'
        ]);
      },
      onStop: (deviceId) async {
        final deviceArgs = deviceId != null ? ['-s', deviceId] : [];
        await Process.run('adb', [
          ...deviceArgs,
          'shell',
          'settings',
          'put',
          'system',
          'show_touches',
          '0'
        ]);
      },
    )
  ];

  String _formatDuration(int ms) {
    final duration = Duration(milliseconds: ms);
    final mInt = duration.inMinutes;
    final m = mInt.toString().padLeft(2, '0');
    final s = duration.inSeconds.remainder(60).toString().padLeft(2, '0');

    return (mInt > 0) ? '$m:$s\tm:s' : '$s\tsec';
  }

  String _formatTimer(int ms) {
    final duration = Duration(milliseconds: ms);
    final m = duration.inMinutes.toString().padLeft(2, '0');
    final s = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final ds = (duration.inMilliseconds % 1000 ~/ 100);
    return '$m:$s.$ds';
  }

  // Text Controllers
  final TextEditingController _categoriesController = TextEditingController();
  final TextEditingController _appNameController = TextEditingController();
  final TextEditingController _outputFileController = TextEditingController();

  bool _autoGenerateFilename = true;

  // ADB Devices
  List<String> _adbDevices = [];
  String? _selectedDevice;

  Future<void> _refreshAdbDevices() async {
    try {
      final result = await Process.run('adb', ['devices']);
      if (result.exitCode == 0) {
        final lines = LineSplitter.split(result.stdout as String).toList();
        final devices = <String>[];
        // Skip first line "List of devices attached"
        for (var i = 1; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.isNotEmpty) {
            final parts = line.split(RegExp(r'\s+'));
            if (parts.length >= 2 && parts[1] == 'device') {
              devices.add(parts[0]);
            }
          }
        }
        setState(() {
          _adbDevices = devices;
          if (_selectedDevice == null ||
              !_adbDevices.contains(_selectedDevice)) {
            _selectedDevice = _adbDevices.isNotEmpty ? _adbDevices.first : null;
          }
        });
      }
    } catch (e) {
      _updateStatus('Error getting devices: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _generateNewFilename();
    _updateBufferSize();
    _refreshAdbDevices();
    // Listen to category text changes to update presets
    _categoriesController.addListener(() {
      if (mounted) setState(() {});
    });
    _appNameController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  void _generateNewFilename() {
    final now = DateTime.now();
    final random = Random();
    final hex =
        random.nextInt(0x10000).toRadixString(16).toLowerCase().padLeft(4, '0');
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final fileName =
        '${now.year}-${twoDigits(now.month)}-${twoDigits(now.day)}_${twoDigits(now.hour)}-${twoDigits(now.minute)}_$hex.pftrace';
    _outputFileController.text = fileName;
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

  /// Parse user input from _categoriesController and split into
  /// atrace categories (no slash) and ftrace events (contains slash).
  List<String> _getUserTokens() {
    return _categoriesController.text
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// All atrace categories = preset modes + user-entered tokens without '/'
  Set<String> _getAtraceCategories() {
    final fromModes = <String>{};
    for (final mode in _recordingModes) {
      if (_selectedModeLabels.contains(mode.label)) {
        fromModes.addAll(mode.atraceCategories);
      }
    }
    final fromUser = _getUserTokens().where((t) => !t.contains('/')).toSet();
    return {...fromModes, ...fromUser};
  }

  /// All ftrace events = defaults + user-entered tokens with '/'
  Set<String> _getFtraceEvents() {
    final fromUser = _getUserTokens().where((t) => t.contains('/')).toSet();
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

  // Process State promt
  bool _isRecording = false;
  bool _userStopped = false;
  Process? _recordingProcess;
  HttpServer? _server;
  Timer? _timer;
  int _elapsedMs = 0;

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
  void _updateStatus(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2)),
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

  // Start Recording
  Future<void> _startRecording() async {
    if (_isRecording) return;

    _lockButton();
    setState(() {
      _isRecording = true;
      _userStopped = false;
      if (_autoGenerateFilename) {
        _generateNewFilename();
      }
    });
    _updateStatus('Starting Perfetto...');

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

      _updateStatus('Recording in progress...');

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
        _updateStatus('Recording finished. Pulling trace...');
        await _pullTraceFile(outputFile);
      } else {
        _updateStatus('Error: Perfetto exited with code $exitCode');
      }
    } catch (e) {
      _updateStatus('Error starting process: $e');
    } finally {
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
    if (_recordingProcess != null) {
      _userStopped = true;
      _updateStatus('Stopping manually...');
      final deviceArgs =
          _selectedDevice != null ? ['-s', _selectedDevice!] : [];
      await Process.run(
          'adb', [...deviceArgs, 'shell', 'killall', '-2', 'perfetto']);
    }
  }

  // Pull Trace File from Device
  Future<void> _pullTraceFile(String traceName) async {
    try {
      final tracesDir = Directory('${Directory.current.path}\\Traces');
      if (!await tracesDir.exists()) {
        await tracesDir.create(recursive: true);
      }
      final localPath = '${tracesDir.path}\\$traceName';

      final deviceArgs =
          _selectedDevice != null ? ['-s', _selectedDevice!] : [];
      final result = await Process.run('adb', [
        ...deviceArgs,
        'pull',
        '/data/misc/perfetto-traces/$traceName',
        localPath
      ]);
      if (result.exitCode == 0) {
        _updateStatus('Success! Saved to $localPath');
      } else {
        _updateStatus('Pull failed: ${result.stderr}');
      }
    } catch (e) {
      _updateStatus('Error pulling file: $e');
    }
  }

  Future<void> _openTraceInBrowser() async {
    final fileName = _outputFileController.text;
    final tracesDir = Directory('${Directory.current.path}\\Traces');
    final filePath = '${tracesDir.path}\\$fileName';

    if (!File(filePath).existsSync()) {
      _updateStatus('File not found: $fileName');
      return;
    }

    // Close existing server
    await _server?.close(force: true);

    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 9001);
      _server!.listen((HttpRequest request) async {
        request.response.headers
            .add('Access-Control-Allow-Origin', 'https://ui.perfetto.dev');
        final encodedName = Uri.encodeComponent(fileName);
        if (request.uri.path == '/$encodedName') {
          final file = File(filePath);
          await file.openRead().pipe(request.response);
        } else {
          request.response.statusCode = HttpStatus.notFound;
          request.response.close();
        }
      });

      final encodedName = Uri.encodeComponent(fileName);
      final url =
          'https://ui.perfetto.dev/#!/?url=http://127.0.0.1:9001/$encodedName&referrer=record_android_trace';

      Process.run('cmd', ['/c', 'start', url]);
      _updateStatus('Serving trace on port 9001...');
    } catch (e) {
      _updateStatus('Error starting server: $e');
    }
  }

  // --- Categories Dialog ---
  void _showCategoriesDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
              child: Text(l10n.activeCategories,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => Navigator.of(ctx).pop(),
              tooltip: l10n.close,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: BoxConstraints(
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
    _categoriesController.dispose();
    _appNameController.dispose();
    _outputFileController.dispose();
    _bufferSizeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        forceMaterialTransparency: true,
        title: Text(l10n.appTitle),
        actions: [
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedDevice,
              isDense: true,
              menuMaxHeight: 300,
              hint: Text(l10n.noDevice, style: const TextStyle(fontSize: 12)),
              selectedItemBuilder: (BuildContext context) {
                return _adbDevices.map<Widget>((String item) {
                  return Row(
                    children: [
                      const Icon(Icons.phone_android, size: 12),
                      const SizedBox(width: 8),
                      Text(item, style: const TextStyle(fontSize: 12)),
                    ],
                  );
                }).toList();
              },
              items: _adbDevices
                  .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedDevice = v),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshAdbDevices,
            tooltip: l10n.refreshDevices,
          ),
        ],
      ),
      body: Column(
        children: [
          // Top Section: Timer & Controls
          Container(
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: Column(
              children: [
                // Row: Timer and Record Button
                Row(
                  children: [
                    // Timer
                    Expanded(
                      flex: 2,
                      child: Column(
                        children: [
                          Text(
                            '${_formatTimer(_elapsedMs)} / ${_formatTimer(_durationMs.toInt())} m:s',
                            style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace'),
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: (_durationMs > 0 && _isRecording)
                                ? (_elapsedMs / _durationMs).clamp(0.0, 1.0)
                                : 0,
                            minHeight: 8,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    // Record Button
                    Expanded(
                      flex: 1,
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton.icon(
                          label: Text(
                            _isRecording ? l10n.stop : l10n.start,
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isRecording
                                ? Colors.redAccent
                                : Colors.blueAccent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _isButtonLocked
                              ? null
                              : (_isRecording
                                  ? _stopRecording
                                  : _startRecording),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Settings Row: Duration Slider
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackShape: const RectangularSliderTrackShape(),
                    trackHeight: 4,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 8),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 16),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.timer_outlined),
                      Text('  ${l10n.maxDuration}',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      Expanded(
                        child: Slider(
                          value: _durationSteps
                              .indexOf(_durationMs.toInt())
                              .toDouble(),
                          min: 0,
                          max: (_durationSteps.length - 1).toDouble(),
                          divisions: _durationSteps.length - 1,
                          label: _formatDuration(_durationMs.toInt()),
                          onChanged: _isRecording
                              ? null
                              : (v) => setState(() {
                                    _durationMs =
                                        _durationSteps[v.toInt()].toDouble();
                                    _updateBufferSize();
                                  }),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Output Trace File (full-width row)
                TextField(
                  controller: _outputFileController,
                  readOnly: _autoGenerateFilename,
                  decoration: InputDecoration(
                    labelText: l10n.outputTraceFile,
                    border: const OutlineInputBorder(),
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    prefixIcon: _autoGenerateFilename
                        ? const Icon(Icons.file_open)
                        : const Icon(Icons.edit_document),
                    suffixIcon: IconButton(
                      iconSize: 16,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: _autoGenerateFilename
                          ? const Icon(Icons.lock)
                          : const Icon(Icons.lock_open),
                      onPressed: () {
                        setState(() {
                          _autoGenerateFilename = !_autoGenerateFilename;
                        });
                      },
                      tooltip: _autoGenerateFilename
                          ? 'Unlock to edit'
                          : 'Lock to auto-generate',
                    ),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),

                // Buffer Size + Action Buttons (merged row)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Buffer Size (compact)
                      SizedBox(
                        width: 125,
                        child: TextField(
                          textAlign: TextAlign.right,
                          controller: _bufferSizeController,
                          readOnly: _autoBufferSize,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: l10n.bufferSize,
                            isDense: true,
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(
                                vertical: 8, horizontal: 12),
                            suffixText: 'MB',
                            suffixIconConstraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                            suffixIcon: IconButton(
                              iconSize: 16,
                              constraints: const BoxConstraints(),
                              padding: EdgeInsets.zero,
                              icon: _autoBufferSize
                                  ? const Icon(Icons.lock)
                                  : const Icon(Icons.lock_open),
                              onPressed: () {
                                setState(() {
                                  _autoBufferSize = !_autoBufferSize;
                                  if (_autoBufferSize) _updateBufferSize();
                                });
                              },
                              tooltip: _autoBufferSize
                                  ? 'Unlock to edit'
                                  : 'Lock to auto-calculate',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Action Buttons
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.folder_open, size: 18),
                          label: Text(l10n.openExplorer,
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          onPressed: () async {
                            final tracesDir =
                                Directory('${Directory.current.path}\\Traces');
                            if (!await tracesDir.exists()) {
                              await tracesDir.create(recursive: true);
                            }
                            final filePath =
                                '${tracesDir.path}\\${_outputFileController.text}';
                            if (File(filePath).existsSync()) {
                              Process.start(
                                  'explorer.exe', ['/select,', filePath]);
                            } else {
                              Process.start('explorer.exe', [tracesDir.path]);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.open_in_browser, size: 18),
                          label: Text(l10n.openPerfetto,
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          onPressed: _openTraceInBrowser,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
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
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _recordingModes.map((m) {
                        final label = m.label;
                        final isSelected = _isModeSelected(label);
                        return FilterChip(
                          showCheckmark: false,
                          avatar: Icon(m.icon, size: 16),
                          label: Text(label),
                          tooltip:
                              m.description.isNotEmpty ? m.description : null,
                          selected: isSelected,
                          onSelected: (v) => _toggleMode(label, v),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Categories Inputs
                  TextField(
                    controller: _categoriesController,
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: "Additional Atrace/Ftrace events",
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.category),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // App Name Input
                  TextField(
                    controller: _appNameController,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: "User process/package names",
                      hintText: "e.g. com.example.app",
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.apps),
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
                          Icon(Icons.category,
                              size: 18,
                              color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            '${l10n.activeCategories}:',
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
                          Icon(Icons.open_in_new,
                              size: 16,
                              color: Theme.of(context).colorScheme.outline),
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
