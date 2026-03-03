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
  final TextEditingController _targetProcessController = TextEditingController(text: 'systemui');
  final TextEditingController _outputFileController = TextEditingController();
  bool _autoGenerateFilename = true;
  bool _isButtonLocked = false;
  
  // Config Toggles
  bool _kernelFrames = true;
  bool _scanAllProcesses = true;

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
    _refreshAdbDevices();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _server?.close(force: true);
    _targetProcessController.dispose();
    _outputFileController.dispose();
    super.dispose();
  }

  // --- Helper Methods (Similar to Recorder) ---

  void _generateNewFilename() {
    final now = DateTime.now();
    final random = Random();
    final hex = random.nextInt(0x10000).toRadixString(16).toLowerCase().padLeft(4, '0');
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final fileName = 'callstack_${now.year}-${twoDigits(now.month)}-${twoDigits(now.day)}_${twoDigits(now.hour)}-${twoDigits(now.minute)}_$hex.pftrace';
    _outputFileController.text = fileName;
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
          if (_selectedDevice == null || !_adbDevices.contains(_selectedDevice)) {
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
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2)),
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
    // If target is empty, match everything (though this might be too verbose for callstacks)
    final filterTerm = target.isNotEmpty ? '*$target*' : '*';
    
    // Construct filters based on the example
    final switchFilter = 'prev_comm ~ \\"$filterTerm\\" || next_comm ~ \\"$filterTerm\\"';
    final wakingFilter = 'comm ~ \\"$filterTerm\\"';

    return '''
duration_ms: $duration

buffers: {
  size_kb: 102400
  fill_policy: DISCARD
}

data_sources {
  config {
    name: "linux.perf"
    perf_event_config {
      timebase {
        period: 1
        tracepoint {
          name: "sched/sched_switch"
          filter: "$switchFilter"
        }
        timestamp_clock: PERF_CLOCK_MONOTONIC
      }
      callstack_sampling {
        kernel_frames: $_kernelFrames
      }
      ring_buffer_pages: 2048
    }
  }
}

data_sources {
  config {
    name: "linux.perf"
    perf_event_config {
      timebase {
        period: 1
        tracepoint {
          name: "sched/sched_waking"
          filter: "$wakingFilter"
        }
        timestamp_clock: PERF_CLOCK_MONOTONIC
      }
      callstack_sampling {
        kernel_frames: $_kernelFrames
      }
      ring_buffer_pages: 2048
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

data_sources: {
  config: {
    name: "linux.process_stats"
    process_stats_config {
      scan_all_processes_on_start: $_scanAllProcesses
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

    final config = _generateConfig();
    final outputFile = _outputFileController.text;
    final deviceArgs = _selectedDevice != null ? ['-s', _selectedDevice!] : [];

    try {
      _recordingProcess = await Process.start(
        'adb', [...deviceArgs, 'shell', 'perfetto', '-c', '-', '--txt', '-o', '"/data/misc/perfetto-traces/$outputFile"'],
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
      final deviceArgs = _selectedDevice != null ? ['-s', _selectedDevice!] : [];
      await Process.run('adb', [...deviceArgs, 'shell', 'killall', '-2', 'perfetto']);
    }
  }

  Future<void> _pullTraceFile(String traceName) async {
    try {
      final tracesDir = Directory('${Directory.current.path}\\Traces');
      if (!await tracesDir.exists()) await tracesDir.create(recursive: true);
      final localPath = '${tracesDir.path}\\$traceName';

      final deviceArgs = _selectedDevice != null ? ['-s', _selectedDevice!] : [];
      final result = await Process.run('adb', [...deviceArgs, 'pull', '/data/misc/perfetto-traces/$traceName', localPath]);
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
        request.response.headers.add('Access-Control-Allow-Origin', 'https://ui.perfetto.dev');
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
      final url = 'https://ui.perfetto.dev/#!/?url=http://127.0.0.1:9001/$encodedName&referrer=record_android_trace';

      Process.run('cmd', ['/c', 'start', url]);
      _updateStatus('Serving trace on port 9001...');
    } catch (e) {
      _updateStatus('Error starting server: $e');
    }
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
              items: _adbDevices.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
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
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: (_durationMs > 0 && _isRecording) ? (_elapsedMs / _durationMs).clamp(0.0, 1.0) : 0,
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
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isRecording ? Colors.redAccent : Colors.blueAccent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _isButtonLocked ? null : (_isRecording ? _stopRecording : _startRecording),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          
          // Settings & Config Display
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Duration Slider
                  Row(
                    children: [
                      const Icon(Icons.timer_outlined),
                      Text('  ${l10n.maxDuration}: ${(_durationMs/1000).toStringAsFixed(0)}s', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Expanded(
                        child: Slider(
                          value: _durationMs,
                          min: 5000,
                          max: 60000,
                          divisions: 11,
                          label: '${(_durationMs/1000).toInt()}s',
                          onChanged: _isRecording ? null : (v) => setState(() => _durationMs = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Target Process Input
                  TextField(
                    controller: _targetProcessController,
                    decoration: const InputDecoration(
                      labelText: 'Target Process (Regex/Glob)',
                      hintText: 'e.g. systemui',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),

                  // Toggles
                  Row(
                    children: [
                      Expanded(
                        child: SwitchListTile(
                          title: const Text('Kernel Frames', style: TextStyle(fontSize: 14)),
                          value: _kernelFrames,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (v) => setState(() => _kernelFrames = v),
                        ),
                      ),
                      Expanded(
                        child: SwitchListTile(
                          title: const Text('Scan All Procs', style: TextStyle(fontSize: 14)),
                          value: _scanAllProcesses,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (v) => setState(() => _scanAllProcesses = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Output File
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _outputFileController,
                          readOnly: _autoGenerateFilename,
                          decoration: InputDecoration(
                            labelText: l10n.outputTraceFile,
                            border: const OutlineInputBorder(),
                            isDense: true,
                            suffixIcon: IconButton(
                              icon: _autoGenerateFilename ? const Icon(Icons.lock) : const Icon(Icons.lock_open),
                              onPressed: () => setState(() => _autoGenerateFilename = !_autoGenerateFilename),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        icon: const Icon(Icons.open_in_browser),
                        tooltip: l10n.openPerfetto,
                        onPressed: _openTraceInBrowser,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Config Preview
                  const Text('Generated Config:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.grey),
                      ),
                      child: SingleChildScrollView(
                        child: Text(
                          _generateConfig(),
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
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