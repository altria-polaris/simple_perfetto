import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'l10n/app_localizations.dart';

class CallStackScreen extends StatefulWidget {
  const CallStackScreen({super.key});

  @override
  State<CallStackScreen> createState() => _CallStackScreenState();
}

class _CallStackScreenState extends State<CallStackScreen> {
  // Config State
  double _durationMs = 10000;
  final TextEditingController _targetProcessController =
      TextEditingController(text: 'com.android.settings');
  final TextEditingController _outputFileController = TextEditingController();
  final TextEditingController _bufferSizeController = TextEditingController();
  final TextEditingController _configController = TextEditingController();
  final TextEditingController _frequencyController =
      TextEditingController(text: '4000');
  bool _autoGenerateFilename = true;
  bool _autoBufferSize = true;
  bool _isButtonLocked = false;

  // Duration steps for the slider
  final List<int> _durationSteps = [
    5000,
    10000,
    15000,
    30000,
    60000,
    180000,
    300000,
    600000,
  ];

  // ADB Devices
  List<String> _adbDevices = [];
  String? _selectedDevice;

  // Recording State
  bool _isRecording = false;
  bool _userStopped = false;
  Process? _recordingProcess;
  Timer? _timer;
  int _elapsedMs = 0;
  HttpServer? _server;

  @override
  void initState() {
    super.initState();
    _generateNewFilename();
    _updateBufferSize();
    _refreshAdbDevices();

    // Auto-update config when parameters change
    _targetProcessController.addListener(_onParamChanged);
    _bufferSizeController.addListener(_onParamChanged);
    _frequencyController.addListener(_onParamChanged);

    // Initial config generation
    _configController.text = _generateConfig();
  }

  void _onParamChanged() {
    if (mounted) {
      setState(() {
        _configController.text = _generateConfig();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _server?.close(force: true);
    _targetProcessController.dispose();
    _outputFileController.dispose();
    _bufferSizeController.dispose();
    _configController.dispose();
    _frequencyController.dispose();
    super.dispose();
  }

  // --- Helper Methods (Similar to Recorder) ---

  void _generateNewFilename() {
    final now = DateTime.now();
    final random = Random();
    final hex =
        random.nextInt(0x10000).toRadixString(16).toLowerCase().padLeft(4, '0');
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final fileName =
        'callstack_${now.year}-${twoDigits(now.month)}-${twoDigits(now.day)}_${twoDigits(now.hour)}-${twoDigits(now.minute)}_$hex.pftrace';
    _outputFileController.text = fileName;
  }

  void _updateBufferSize() {
    if (_autoBufferSize) {
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
      } else {
        sizeMb = 1024;
      }
      sizeMb = sizeMb.clamp(16, 4096);
      _bufferSizeController.text = sizeMb.toString();
    }
  }

  String _formatTimer(int ms) {
    final duration = Duration(milliseconds: ms);
    final m = duration.inMinutes.toString().padLeft(2, '0');
    final s = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final ds = (duration.inMilliseconds % 1000 ~/ 100);
    return '$m:$s.$ds';
  }

  Future<void> _refreshAdbDevices() async {
    try {
      final result = await Process.run('adb', ['devices']);
      if (result.exitCode == 0) {
        final lines = LineSplitter.split(result.stdout as String).toList();
        final devices = <String>[];
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

  void _lockButton() {
    setState(() => _isButtonLocked = true);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _isButtonLocked = false);
    });
  }

  // --- Config Generation ---

  String _generateConfig() {
    final duration = _durationMs.toInt();
    final target = _targetProcessController.text.trim();
    int bufferSizeKb = 102400;
    try {
      bufferSizeKb = int.parse(_bufferSizeController.text) * 1024;
    } catch (_) {}

    int frequency = 4000;
    try {
      frequency = int.parse(_frequencyController.text);
    } catch (_) {}

    return '''
duration_ms: $duration

buffers: {
  size_kb: $bufferSizeKb
  fill_policy: DISCARD
}

data_sources {
  config {
    name: "linux.perf"
    perf_event_config {
      timebase {
        frequency: $frequency
        timestamp_clock: PERF_CLOCK_MONOTONIC
      }
      callstack_sampling {
        scope {
          target_cmdline: "$target"
        }
        kernel_frames: true
      }
    }
  }
}

data_sources: {
  config: {
    name: "linux.ftrace"
    ftrace_config: {
      ftrace_events: "sched/sched_switch"
      ftrace_events: "sched/sched_waking"
      atrace_categories: "dalvik"
      atrace_categories: "gfx"
      atrace_categories: "view"
    }
  }
}
''';
  }

  // --- Recording Logic ---

  Future<void> _startRecording() async {
    if (_isRecording) return;

    _lockButton();
    setState(() {
      _isRecording = true;
      _userStopped = false;
      if (_autoGenerateFilename) _generateNewFilename();
    });
    _updateStatus('Starting Perfetto (CallStack)...');

    final config = _configController.text;
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

      _recordingProcess!.stdin.write(config);
      await _recordingProcess!.stdin.flush();
      await _recordingProcess!.stdin.close();

      _updateStatus('Recording in progress...');

      _elapsedMs = 0;
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(milliseconds: 100), (t) {
        setState(() {
          _elapsedMs += 100;
          if (_elapsedMs >= _durationMs) _elapsedMs = _durationMs.toInt();
        });
      });

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

  Future<void> _pullTraceFile(String traceName) async {
    try {
      final tracesDir = Directory('${Directory.current.path}\\Traces');
      if (!await tracesDir.exists()) await tracesDir.create(recursive: true);
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

  // --- Config Dialog ---
  void _showConfigDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        title: Row(
          children: [
            Icon(Icons.settings_applications,
                size: 20, color: Theme.of(ctx).colorScheme.primary),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Perfetto Config (Editable)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
            maxHeight: MediaQuery.of(ctx).size.height * 0.7,
            maxWidth: 500,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Manual edits here will be used for the next recording.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.grey.shade800),
                  ),
                  child: TextField(
                    controller: _configController,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(
                        color: Colors.greenAccent,
                        fontFamily: 'monospace',
                        fontSize: 12),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _configController.text = _generateConfig();
              });
            },
            child: const Text('Reset to Default'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        forceMaterialTransparency: true,
        title: Text(l10n.callStack),
        actions: [
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedDevice,
              isDense: true,
              menuMaxHeight: 300,
              hint: Text(l10n.noDevice, style: const TextStyle(fontSize: 12)),
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
                Row(
                  children: [
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

                // Duration Slider
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackShape: const RectangularSliderTrackShape(),
                    trackHeight: 2,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.timer_outlined, size: 18),
                      Text('  ${l10n.maxDuration}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      Expanded(
                        child: Slider(
                          value: _durationSteps
                              .indexOf(_durationMs.toInt())
                              .toDouble(),
                          min: 0,
                          max: (_durationSteps.length - 1).toDouble(),
                          divisions: _durationSteps.length - 1,
                          label: '${(_durationMs / 1000).toInt()}s',
                          onChanged: _isRecording
                              ? null
                              : (v) => setState(() {
                                    _durationMs =
                                        _durationSteps[v.toInt()].toDouble();
                                    _updateBufferSize();
                                    _configController.text = _generateConfig();
                                  }),
                        ),
                      ),
                    ],
                  ),
                ),

                // Output Trace File
                TextField(
                  controller: _outputFileController,
                  readOnly: _autoGenerateFilename,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    labelText: l10n.outputTraceFile,
                    border: const OutlineInputBorder(),
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    prefixIcon: _autoGenerateFilename
                        ? const Icon(Icons.file_open, size: 18)
                        : const Icon(Icons.edit_document, size: 18),
                    suffixIcon: IconButton(
                      iconSize: 16,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: _autoGenerateFilename
                          ? const Icon(Icons.lock)
                          : const Icon(Icons.lock_open),
                      onPressed: () => setState(
                          () => _autoGenerateFilename = !_autoGenerateFilename),
                      tooltip: _autoGenerateFilename
                          ? 'Unlock to edit'
                          : 'Lock to auto-generate',
                    ),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),

                // Buffer Size + Action Buttons
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 110,
                        child: TextField(
                          textAlign: TextAlign.right,
                          controller: _bufferSizeController,
                          readOnly: _autoBufferSize,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            labelText: l10n.bufferSize,
                            isDense: true,
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(
                                vertical: 8, horizontal: 12),
                            suffixText: 'MB',
                            suffixIcon: IconButton(
                              iconSize: 14,
                              constraints: const BoxConstraints(),
                              padding: EdgeInsets.zero,
                              icon: _autoBufferSize
                                  ? const Icon(Icons.auto_fix_normal)
                                  : const Icon(Icons.auto_fix_off),
                              onPressed: () => setState(() {
                                _autoBufferSize = !_autoBufferSize;
                                if (_autoBufferSize) _updateBufferSize();
                              }),
                              tooltip: _autoBufferSize
                                  ? 'Unlock'
                                  : 'Lock to auto-calculate',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.folder_open, size: 16),
                          label: Text(l10n.openExplorer,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13)),
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
                          icon: const Icon(Icons.open_in_browser, size: 16),
                          label: Text(l10n.openPerfetto,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13)),
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

          // Settings Section
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _targetProcessController,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'Target Process (Cmdline)',
                      hintText: 'e.g. com.android.settings',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.search, size: 18),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _frequencyController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'Frequency (Hz)',
                      hintText: 'e.g. 4000',
                      suffixText: 'samples/s',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.speed, size: 18),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Config Dialog Trigger (Similar to Active Categories in Recorder)
                  InkWell(
                    onTap: () => _showConfigDialog(context),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color:
                            Theme.of(context).colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: Theme.of(context).dividerColor),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.settings_applications, size: 20),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Perfetto configuration',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  'Click to manually edit generated configuration',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ],
                            ),
                          ),
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
}
