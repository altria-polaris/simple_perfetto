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
  final TextEditingController _bufferSizeController = TextEditingController();
  bool _autoBufferSize = true;

  // Duration steps for the slider
  final List<int> _durationSteps = [
       10000,   15000,   30000,   60000,
      180000,  300000,  600000,  900000,
     1800000, 3600000
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
  final TextEditingController _categoriesController = TextEditingController();
  final TextEditingController _appNameController = TextEditingController();
  final TextEditingController _outputFileController = TextEditingController();
  final ScrollController _activeCategoriesScrollController = ScrollController();
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
    _updateBufferSize();
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

  void _updateBufferSize() {
    if (_autoBufferSize) {
      // Auto-calculate buffer size: ~10MB per second
      int durationSec = _durationMs ~/ 1000;
      int sizeMb = durationSec * 10;
      if (sizeMb < 32) sizeMb = 32;
      if (sizeMb > 2048) sizeMb = 2048;
      _bufferSizeController.text = sizeMb.toString();
    }
  }

  // Selected Presets
  final Set<String> _selectedPresetLabels = {'Basic'};

  // Toggle Preset
  void _togglePreset(String label, bool selected) {
    setState(() {
      if (selected) {
        _selectedPresetLabels.add(label);
      } else {
        _selectedPresetLabels.remove(label);
      }
    });
  }

  // Check if preset is selected
  bool _isPresetSelected(String label) {
    return _selectedPresetLabels.contains(label);
  }

  Set<String> _getAllCategories() {
    final manualTags = _categoriesController.text.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toSet();
    final presetTags = <String>{};
    for (final preset in _atracePresets) {
      if (_selectedPresetLabels.contains(preset['label'])) {
        final tags = (preset['tags'] as String).trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty);
        presetTags.addAll(tags);
      }
    }
    return {...presetTags, ...manualTags};
  }

  // Process State promt
  bool _isRecording = false;
  bool _userStopped = false;
  Process? _recordingProcess;
  HttpServer? _server;
  Timer? _timer;
  int _elapsedMs = 0;

  // Update Status Message
  void _updateStatus(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 5)),
    );
  }

  // Config Generator
  String _generateConfig() {
    final duration = _durationMs.toInt();
    int bufferSizeKb = 32 * 1024;
    try {
      bufferSizeKb = int.parse(_bufferSizeController.text) * 1024;
    } catch (_) {}
    final categories = _getAllCategories().toList();
    final appName = _appNameController.text.trim();

    String atraceLines = categories.map((c) => '      atrace_categories: "$c"').join('\n');
    if (appName.isNotEmpty) {
      atraceLines += '\n      atrace_apps: "$appName"';
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
    _appNameController.dispose();
    _outputFileController.dispose();
    _bufferSizeController.dispose();
    _activeCategoriesScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        forceMaterialTransparency: true,
        title: const Text('Simple Perfetto Recorder'),
        actions: [
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedDevice,
              isDense: true,
              menuMaxHeight: 300,
              hint: const Text('No Device'),
              selectedItemBuilder: (BuildContext context) {
                return _adbDevices.map<Widget>((String item) {
                  return Row(
                    children: [
                      const Icon(Icons.phone_android, size: 18),
                      const SizedBox(width: 8),
                      Text(item),
                    ],
                  );
                }).toList();
              },
              items: _adbDevices.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
              onChanged: (v) => setState(() => _selectedDevice = v),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshAdbDevices,
            tooltip: 'Refresh Devices',
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
                            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: (_durationMs > 0 && _isRecording)  ? (_elapsedMs / _durationMs).clamp(0.0, 1.0) : 0,
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

                // Settings Row: Duration & Buffer
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackShape: const RectangularSliderTrackShape(),
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.timer_outlined),
                      const Text('  Max Duration', style: TextStyle(fontWeight: FontWeight.bold)),
                      Expanded(
                        flex: 1,
                        child: Slider(
                          value: _durationSteps.indexOf(_durationMs.toInt()).toDouble(),
                          min: 0,
                          max: (_durationSteps.length - 1).toDouble(),
                          divisions: _durationSteps.length - 1,
                          label: _formatDuration(_durationMs.toInt()),
                          onChanged: _isRecording ? null : (v) => setState(() {
                            _durationMs = _durationSteps[v.toInt()].toDouble();
                            _updateBufferSize();
                          }),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Icon(Icons.restore_outlined),
                      const Text('  Buffer Size', style: TextStyle(fontWeight: FontWeight.bold)),
                      Expanded(
                        flex: 1,
                        child: TextField(
                          controller: _bufferSizeController,
                          readOnly: _autoBufferSize,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                            suffixText: 'MB',
                            suffixIcon: IconButton(
                              iconSize: 16,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              icon: _autoBufferSize ? const Icon(Icons.lock) : const Icon(Icons.lock_open),
                              onPressed: () {
                                setState(() {
                                  _autoBufferSize = !_autoBufferSize;
                                  if (_autoBufferSize) _updateBufferSize();
                                });
                              },
                              tooltip: _autoBufferSize ? 'Unlock to edit' : 'Lock to auto-calculate',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Output Path
                TextField(
                  controller: _outputFileController,
                  readOnly: _autoGenerateFilename,
                  decoration: InputDecoration(
                    labelText: 'Output Trace File',
                    border: const OutlineInputBorder(),
                    prefixIcon: _autoGenerateFilename ? const Icon(Icons.file_open) : const Icon(Icons.edit_document),
                    suffixIcon: IconButton(
                      icon: _autoGenerateFilename ? const Icon(Icons.lock) : const Icon(Icons.lock_open),
                      onPressed: () {
                        setState(() {
                          _autoGenerateFilename = !_autoGenerateFilename;
                        });
                      },
                      tooltip: _autoGenerateFilename ? 'Unlock to edit' : 'Lock to auto-generate',
                    ),
                    isDense: true,
                  ),
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
                    const SizedBox(width: 20),
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
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                        final label = p['label'] as String;
                        final isSelected = _isPresetSelected(label);
                        return FilterChip(
                          showCheckmark: false,
                          avatar: Icon(p['icon'] as IconData, size: 16),
                          label: Text(label),
                          selected: isSelected,
                          onSelected: (v) => _togglePreset(label, v),
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
                      labelText: 'Manual Categories',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.category),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // App Name Input
                  TextField(
                    controller: _appNameController,
                    decoration: const InputDecoration(
                      labelText: 'App Name (atrace_apps)',
                      hintText: 'e.g. com.example.app',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.apps),
                      isDense: true,
                    ),
                  ),

                  // Active Categories Display
                  if (_getAllCategories().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildSectionTitle('Active Categories'),
                    Expanded(
                      child: Container(
                        clipBehavior: Clip.hardEdge,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Theme.of(context).dividerColor),
                        ),
                        child: Scrollbar(
                          controller: _activeCategoriesScrollController,
                          thumbVisibility: true,
                          child: GridView.extent(
                            controller: _activeCategoriesScrollController,
                            maxCrossAxisExtent: 120,
                            padding: EdgeInsets.zero,
                            mainAxisSpacing: 0,
                            crossAxisSpacing: 0,
                            childAspectRatio: 4,
                            children: _getAllCategories().map((tag) => Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.5)),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                tag,
                                style: const TextStyle(fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            )).toList(),
                          ),
                        ),
                      ),
                    ),
                  ],
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
