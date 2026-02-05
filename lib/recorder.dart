import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';

class RecorderScreen extends StatefulWidget {
  const RecorderScreen({super.key});

  @override
  State<RecorderScreen> createState() => _RecorderScreenState();
}

class _RecorderScreenState extends State<RecorderScreen> {
  double _durationMs = 10000;
  double _bufferSizeMbExponent = 6;  // buffer size exponent for power of two

  // Duration steps for the slider
  final List<int> _durationSteps = [
       10000,   15000,   30000,   60000,
      180000,  300000,  600000,  900000,
     1800000, 2700000, 3600000
  ];

  final List<Map<String, dynamic>> _atracePresets = [
    {
      'label': 'Basic',
      'icon': Icons.phone_android,
      'tags': 'gfx input view wm am',
    },
    {
      'label': 'Camera',
      'icon': Icons.camera_alt,
      'tags': 'camera hal video ion gfx sched freq idle',
    },
    {
      'label': 'Graphic',
      'icon': Icons.videogame_asset,
      'tags': 'gfx sched freq idle',
    },
    {
      'label': 'Kernel',
      'icon': Icons.developer_board,
      'tags': 'sched freq idle irq workq disk sync',
    },
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
  final TextEditingController _categoriesController = TextEditingController(text: 'gfx view sched freq idle am wm',);
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
          if (_selectedDevice == null || !_adbDevices.contains(_selectedDevice)) {
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
    _refreshAdbDevices();
    // Listen to category text changes to update presets
    _categoriesController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  void _generateNewFilename() {
    final now = DateTime.now();
    final random = Random();
    final hex = random.nextInt(0x10000).toRadixString(16).toLowerCase().padLeft(4, '0');
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final fileName = '${now.year}-${twoDigits(now.month)}-${twoDigits(now.day)}_${twoDigits(now.hour)}-${twoDigits(now.minute)}_$hex.pftrace';
    _outputFileController.text = fileName;
  }

  // Toggle Preset Tags
  void _togglePreset(String tags, bool selected) {
    final currentTags = _categoriesController.text.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toSet();
    final presetTags = tags.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toSet();

    if (selected) {
      currentTags.addAll(presetTags); // accumulate tags
    } else {
      final tagsToKeep = <String>{};
      for (final preset in _atracePresets) {
        final pTagsStr = preset['tags'] as String;
        if (pTagsStr == tags) continue; // skip itself

        final pTags = pTagsStr.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toSet();
        // Check if this preset is currently satisfied by the text field (before removal)
        if (pTags.isNotEmpty && currentTags.containsAll(pTags)) {
          tagsToKeep.addAll(pTags);
        }
      }
      currentTags.removeAll(presetTags.difference(tagsToKeep));
    }
    _categoriesController.text = currentTags.join(' ');
  }

  // Check if preset is selected
  bool _isPresetSelected(String tags) {
    final currentTags = _categoriesController.text.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toSet();
    final presetTags = tags.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toSet();
    return presetTags.isNotEmpty && currentTags.containsAll(presetTags);
  }

  // Process State promt
  bool _isRecording = false;
  bool _userStopped = false;
  String _statusMessage = 'Ready to record.';
  Process? _recordingProcess;
  HttpServer? _server;
  Timer? _timer;
  int _elapsedMs = 0;

  // Update Status Message
  void _updateStatus(String message) {
    setState(() {
      _statusMessage = message;
    });
  }

  // Config Generator
  String _generateConfig() {
    final duration = _durationMs.toInt();
    final bufferSizeKb = pow(2, _bufferSizeMbExponent).toInt() * 1024;
    final categories = _categoriesController.text.trim().split(' ').where((s) => s.isNotEmpty).toList();

    String atraceLines = categories.map((c) => '      atrace_categories: "$c"').join('\n');

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
            ftrace_events: "sched/sched_switch"
            ftrace_events: "power/suspend_resume"
            ftrace_events: "ftrace/print"
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

    setState(() {
      _isRecording = true;
      _userStopped = false;
      _statusMessage = 'Starting Perfetto...';
      if (_autoGenerateFilename) {
        _generateNewFilename();
      }
    });

    final config = _generateConfig();
    final outputFile = _outputFileController.text;

    final deviceArgs = _selectedDevice != null ? ['-s', _selectedDevice!] : [];
    try {
      _recordingProcess = await Process.start(
        'adb', [...deviceArgs, 'shell', 'perfetto', '-c', '-', '--txt', '-o', '"/data/misc/perfetto-traces/$outputFile"'],
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
    if (_recordingProcess != null) {
      _userStopped = true;
      _updateStatus('Stopping manually...');
      final deviceArgs = _selectedDevice != null ? ['-s', _selectedDevice!] : [];
      await Process.run('adb', [...deviceArgs, 'shell', 'killall', '-2', 'perfetto']);
    }
  }

  // Pull Trace File from Device
  Future<void> _pullTraceFile(String traceName) async {
    try {
      final deviceArgs = _selectedDevice != null ? ['-s', _selectedDevice!] : [];
      final result = await Process.run('adb', [...deviceArgs, 'pull', '/data/misc/perfetto-traces/$traceName', traceName]);
      if (result.exitCode == 0) {
        _updateStatus('Success! Saved to $traceName');
      } else {
        _updateStatus('Pull failed: ${result.stderr}');
      }
    } catch (e) {
      _updateStatus('Error pulling file: $e');
    }
  }

  Future<void> _openTraceInBrowser() async {
    final fileName = _outputFileController.text;
    final filePath = '${Directory.current.path}\\$fileName';

    if (!File(filePath).existsSync()) {
      _updateStatus('File not found: $fileName');
      return;
    }

    // Close existing server
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
  void dispose() {
    _timer?.cancel();
    _server?.close(force: true);
    _categoriesController.dispose();
    _outputFileController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Simple Perfetto Recorder'),
      ),
      body: Column(
        children: [
          // Top Section: Timer & Controls
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: Column(
              children: [
                // Row: Timer and Record Button
                Row(
                  children: [
                    // Timer
                    Expanded(
                      flex: 4,
                      child: Column(
                        children: [
                          Text(
                            '${_formatTimer(_elapsedMs)} / ${_formatTimer(_durationMs.toInt())}',
                            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: _durationMs > 0 ? (_elapsedMs / _durationMs).clamp(0.0, 1.0) : 0,
                            minHeight: 8,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    // Record Button
                    Expanded(
                      flex: 3,
                      child: SizedBox(
                        height: 56,
                        child: ElevatedButton.icon(

                          label: Text(
                            _isRecording ? 'STOP' : 'START RECORDING',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isRecording ? Colors.redAccent : Colors.blueAccent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _isRecording ? _stopRecording : _startRecording,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Device Selector
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedDevice,
                        decoration: const InputDecoration(
                          labelText: 'Target Device',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.phone_android),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        items: _adbDevices.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                        onChanged: (v) => setState(() => _selectedDevice = v),
                        hint: const Text('No devices found'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _refreshAdbDevices,
                      tooltip: 'Refresh Devices',
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Output Path
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _outputFileController,
                        decoration: const InputDecoration(
                          labelText: 'Output Trace File',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.save_alt),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(value: _autoGenerateFilename, onChanged: (v) => setState(() => _autoGenerateFilename = v ?? true)),
                        const Text('random', style: TextStyle(fontSize: 10)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Open Explorer'),
                        onPressed: () {
                          final filePath = '${Directory.current.path}\\${_outputFileController.text}';
                          if (File(filePath).existsSync()) {
                            Process.run('explorer.exe', ['/select,', filePath]);
                          } else {
                            Process.run('explorer.exe', [Directory.current.path]);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.open_in_browser),
                        label: const Text('Open Perfetto'),
                        onPressed: _openTraceInBrowser,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Bottom Section: Settings (Scrollable)
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Sliders
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackShape: const RectangularSliderTrackShape(),
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionTitle('Recording Duration'),
                              Row(
                                children: [
                                  const Icon(Icons.timer, color: Colors.white70),
                                  Expanded(
                                    child: Slider(
                                      value: _durationSteps.indexOf(_durationMs.toInt()).toDouble(),
                                      min: 0,
                                      max: (_durationSteps.length - 1).toDouble(),
                                      divisions: _durationSteps.length - 1,
                                      label: _formatDuration(_durationMs.toInt()),
                                      onChanged: _isRecording ? null : (v) => setState(() => _durationMs = _durationSteps[v.toInt()].toDouble()),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 80,
                                    child: Text(
                                      _formatDuration(_durationMs.toInt()),
                                      textAlign: TextAlign.end,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionTitle('Ring Buffer Size'),
                              Row(
                                children: [
                                  const Icon(Icons.memory, color: Colors.white70),
                                  Expanded(
                                    child: Slider(
                                      value: _bufferSizeMbExponent,
                                      min: 5,
                                      max: 11,
                                      divisions: 6,
                                      label: '${pow(2, _bufferSizeMbExponent).toInt()} MB',
                                      onChanged: _isRecording ? null : (v) => setState(() => _bufferSizeMbExponent = v),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 70,
                                    child: Text(
                                      '${pow(2, _bufferSizeMbExponent).toInt()} MB',
                                      textAlign: TextAlign.end,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),
                  //Quick Presets
                  _buildSectionTitle('Quick Presets'),
                  Theme(
                    data: Theme.of(context).copyWith(
                      splashFactory: NoSplash.splashFactory,
                      highlightColor: Colors.transparent,
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _atracePresets.map((p) {
                        final tags = p['tags'] as String;
                        final isSelected = _isPresetSelected(tags);
                        return FilterChip(
                          showCheckmark: false,
                          avatar: Icon(p['icon'] as IconData, size: 16),
                          label: Text(p['label'] as String),
                          selected: isSelected,
                          onSelected: (v) => _togglePreset(tags, v),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Categories Inputs
                  TextField(
                    controller: _categoriesController,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: const InputDecoration(
                      labelText: 'Additional Categories',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.category),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Bottom Fixed Section (Status Bar Only)
          Container(
            padding: const EdgeInsets.all(24),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _statusMessage,
                      style: const TextStyle(fontFamily: 'monospace', color: Colors.white70),
                      overflow: TextOverflow.ellipsis,
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
        style: const TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.bold),
      ),
    );
  }
}
