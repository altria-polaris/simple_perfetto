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
  double _bufferSizeMb = 64;

  // Duration steps for the slider
  final List<int> _durationSteps = [
    10000, 15000, 30000, 60000,
    180000, 300000, 600000, 900000,
    1800000, 3600000
  ];

  String _formatDuration(int ms) {
    final duration = Duration(milliseconds: ms);
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);
    final s = duration.inSeconds.remainder(60);
    return '${h}h ${m}m ${s}s';
  }

  // Text Controllers
  final TextEditingController _categoriesController = TextEditingController(text: 'gfx view sched freq idle am wm',);
  final TextEditingController _outputFileController = TextEditingController();
  bool _autoGenerateFilename = true;

  @override
  void initState() {
    super.initState();
    _generateNewFilename();
  }

  void _generateNewFilename() {
    final now = DateTime.now();
    final random = Random();
    final hex = random.nextInt(0x10000).toRadixString(16).toLowerCase().padLeft(4, '0');
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final fileName = '${now.year}-${twoDigits(now.month)}-${twoDigits(now.day)}_${twoDigits(now.hour)}_${twoDigits(now.minute)}_$hex.pftrace';
    _outputFileController.text = fileName;
  }

  // Process State promt
  bool _isRecording = false;
  String _statusMessage = 'Ready to record.';
  Process? _recordingProcess;

  // Update Status Message
  void _updateStatus(String message) {
    setState(() {
      _statusMessage = message;
    });
  }

  // Config Generator
  String _generateConfig() {
    final duration = _durationMs.toInt();
    final bufferSizeKb = _bufferSizeMb.toInt() * 1024;
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
      _statusMessage = 'Starting Perfetto...';
    });

    final config = _generateConfig();
    final outputFile = _outputFileController.text;

    try {
      _recordingProcess = await Process.start(
        'adb', ['shell', 'perfetto', '-c', '-', '--txt', '-o', '/data/misc/perfetto-traces/$outputFile'],
      );

      // Write config to stdin
      _recordingProcess!.stdin.write(config);
      await _recordingProcess!.stdin.flush();
      await _recordingProcess!.stdin.close();

      _updateStatus('Recording in progress... (${(_durationMs/1000).toStringAsFixed(1)}s)');

      // Wait for process to complete
      final exitCode = await _recordingProcess!.exitCode;
      
      if (exitCode == 0) {
        _updateStatus('Recording finished. Pulling trace...');
        await _pullTraceFile(outputFile);
        if (_autoGenerateFilename) {
          setState(() {
            _generateNewFilename();
          });
        }
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
        });
      }
    }
  }

  // Manual Stop Recording
  Future<void> _stopRecording() async {
    if (_recordingProcess != null) {
      _updateStatus('Stopping manually...');
      _recordingProcess!.kill(ProcessSignal.sigterm);
    }
  }

  // Pull Trace File from Device
  Future<void> _pullTraceFile(String traceName) async {
    try {
      final result = await Process.run('adb', ['pull', '/data/misc/perfetto-traces/$traceName', traceName]);
      if (result.exitCode == 0) {
        _updateStatus('Success! Saved to $traceName');
      } else {
        _updateStatus('Pull failed: ${result.stderr}');
      }
    } catch (e) {
      _updateStatus('Error pulling file: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Simple Perfetto Recorder'),
        actions: [
          if (_isRecording)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: IconButton(
                icon: const Icon(Icons.stop_circle, color: Colors.redAccent, size: 32),
                onPressed: _stopRecording,
                tooltip: 'Stop Recording Now',
              ),
            )
        ],
      ),
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Time Slider
              _buildSectionTitle('Recording Duration'),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                   const Icon(Icons.timer, color: Colors.white70),
                   const SizedBox(width: 10),
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
                     width: 100,
                     child: Text(
                       _formatDuration(_durationMs.toInt()),
                       textAlign: TextAlign.end,
                       style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                     ),
                   ),
                ],
              ),
              const SizedBox(height: 20),

              // Buffer Size Slider
              _buildSectionTitle('Ring Buffer Size'),
              Row(
                children: [
                   const Icon(Icons.memory, color: Colors.white70),
                   const SizedBox(width: 10),
                   Expanded(
                     child: Slider(
                      value: _bufferSizeMb,
                      min: 32,
                      max: 1024, // max 1024 MB
                      divisions: 63,
                      label: '${_bufferSizeMb.round()} MB',
                      onChanged: _isRecording ? null : (v) => setState(() => _bufferSizeMb = v),
                                     ),
                   ),
                   SizedBox(
                     width: 80,
                     child: Text(
                       '${_bufferSizeMb.toInt()} MB', 
                       textAlign: TextAlign.end,
                       style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                     ),
                   ),
                ],
              ),
              
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 10),

              // Categories Inputs
              TextField(
                controller: _categoriesController,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  labelText: 'Atrace Categories',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),
              
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
                  Checkbox(value: _autoGenerateFilename, onChanged: (v) => setState(() => _autoGenerateFilename = v ?? true)),
                  const Text('Random Filename'),
                ],
              ),

              const Spacer(), // Push to bottom

              // Main Record Button
              SizedBox(
                height: 56,
                child: ElevatedButton.icon(
                  icon: _isRecording 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                      : const Icon(Icons.fiber_manual_record),
                  label: Text(
                    _isRecording ? 'RECORDING IN PROGRESS...' : 'START RECORDING',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isRecording ? Colors.grey.shade800 : Colors.blueAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isRecording ? null : _startRecording,
                ),
              ),
              
              // Bottom Status Bar
              Container(
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
            ],
          ),
        ),
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
