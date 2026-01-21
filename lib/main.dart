import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    await windowManager.setSize(const Size(1024, 768));
    await windowManager.setAlignment(Alignment.center);
    await windowManager.show();
  }
  runApp(const PerfettoRecorderApp());
}

class PerfettoRecorderApp extends StatelessWidget {
  const PerfettoRecorderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Perfetto UI Recorder',
      theme: ThemeData(
        primarySwatch: Colors.blueGrey,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const RecorderScreen(),
    );
  }
}

class RecorderScreen extends StatefulWidget {
  const RecorderScreen({super.key});

  @override
  State<RecorderScreen> createState() => _RecorderScreenState();
}

class _RecorderScreenState extends State<RecorderScreen> {
  // UI Controllers
  final TextEditingController _durationController = TextEditingController(text: '10000');
  final TextEditingController _bufferSizeController = TextEditingController(text: '64');
  final TextEditingController _categoriesController = TextEditingController(text: 'gfx view sched freq idle am wm');
  final TextEditingController _outputFileController = TextEditingController(text: '/data/local/tmp/trace.perfetto-trace');
  final TextEditingController _markerController = TextEditingController(text: 'User_Marker_Event');

  // State
  bool _isRecording = false;
  String _statusLog = 'Ready to record.\n';
  Process? _recordingProcess;

  // Append log to the on-screen console
  void _log(String message) {
    setState(() {
      _statusLog += '[${DateTime.now().toIso8601String().substring(11, 19)}] $message\n';
    });
  }

  // Generate Perfetto Text Proto Configuration
  String _generateConfig() {
    final durationMs = int.tryParse(_durationController.text) ?? 10000;
    final bufferSizeKb = (int.tryParse(_bufferSizeController.text) ?? 64) * 1024;
    final categories = _categoriesController.text.trim().split(' ').where((s) => s.isNotEmpty).toList();

    // Constructing atrace categories lines
    String atraceLines = categories.map((c) => '      atrace_categories: "$c"').join('\n');

    return '''
buffers: {
    size_kb: $bufferSizeKb
    fill_policy: RING_BUFFER
}
duration_ms: $durationMs

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
      _statusLog = ''; // Clear log on new run
    });

    final config = _generateConfig();
    final outputFile = _outputFileController.text;

    _log('Generating Config:\n$config');
    _log('Starting Perfetto on device...');

    try {
      // Execute adb shell perfetto
      // We pipe the config to stdin using "-c -"
      _recordingProcess = await Process.start(
        'adb',
        ['shell', 'perfetto', '-c', '-', '--txt', '-o', outputFile],
      );

      // Write config to stdin
      _recordingProcess!.stdin.write(config);
      await _recordingProcess!.stdin.flush();
      await _recordingProcess!.stdin.close();

      // Listen to stdout/stderr
      _recordingProcess!.stdout.transform(utf8.decoder).listen((data) {
        _log('STDOUT: $data');
      });
      
      _recordingProcess!.stderr.transform(utf8.decoder).listen((data) {
        _log('STDERR: $data');
      });

      // Wait for process to exit (when duration ends or manual stop)
      final exitCode = await _recordingProcess!.exitCode;
      _log('Recording finished with exit code $exitCode');
      
      // Pull the file automatically
      _pullTraceFile(outputFile);

    } catch (e) {
      _log('Error starting process: $e');
    } finally {
      setState(() {
        _isRecording = false;
        _recordingProcess = null;
      });
    }
  }

  // Stop Recording Manually (SIGTERM)
  Future<void> _stopRecording() async {
    if (_recordingProcess != null) {
      _log('Stopping recording manually...');
      // Ideally, we find the PID and kill it, but Process.kill() kills the local adb client, 
      // which usually propagates the signal.
      _recordingProcess!.kill(ProcessSignal.sigterm);
    }
  }

  // Pull trace file from device
  Future<void> _pullTraceFile(String remotePath) async {
    _log('Pulling trace file to Desktop...');
    try {
      final result = await Process.run('adb', ['pull', remotePath, 'trace.perfetto-trace']);
      if (result.exitCode == 0) {
        _log('Success! Saved to ./trace.perfetto-trace');
      } else {
        _log('Pull failed: ${result.stderr}');
      }
    } catch (e) {
      _log('Error pulling file: $e');
    }
  }

  // Inject a custom event into ftrace marker (Live)
  Future<void> _injectCustomEvent() async {
    final label = _markerController.text;
    if (label.isEmpty) return;

    _log('Injecting marker: $label');
    try {
      // Writing to trace_marker allows adding events from user-space into the kernel trace
      // Format: B|PID|TITLE for begin, E for end. Simple string is a point event.
      // Here we just write a print event.
      await Process.run('adb', [
        'shell', 
        'echo "trace_event_clock_sync: name=$label" > /sys/kernel/tracing/trace_marker'
      ]);
      // Note: On some older Androids path might be /sys/kernel/debug/tracing/trace_marker
    } catch (e) {
      _log('Failed to inject marker: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfetto Desktop Recorder'),
        actions: [
           if (_isRecording)
            IconButton(
              icon: const Icon(Icons.stop_circle, color: Colors.red),
              onPressed: _stopRecording,
              tooltip: 'Stop Recording',
            )
        ],
      ),
      body: Row(
        children: [
          // Left Panel: Settings
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.all(16),
              color: Colors.black12,
              child: ListView(
                children: [
                  const Text('Configuration', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  
                  // Duration
                  TextField(
                    controller: _durationController,
                    decoration: const InputDecoration(
                      labelText: 'Duration (ms)',
                      border: OutlineInputBorder(),
                      suffixText: 'ms',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  
                  // Ring Buffer Size
                  TextField(
                    controller: _bufferSizeController,
                    decoration: const InputDecoration(
                      labelText: 'Buffer Size (MB)',
                      border: OutlineInputBorder(),
                      suffixText: 'MB',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  
                  // Categories
                  TextField(
                    controller: _categoriesController,
                    decoration: const InputDecoration(
                      labelText: 'Atrace Categories (space separated)',
                      border: OutlineInputBorder(),
                      helperText: 'e.g. gfx view sched wm am',
                    ),
                    maxLines: 3,
                  ),
                   const SizedBox(height: 16),

                  // Output Path
                  TextField(
                    controller: _outputFileController,
                    decoration: const InputDecoration(
                      labelText: 'Device Output Path',
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 30),
                  
                  // Action Buttons
                  SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      icon: Icon(_isRecording ? Icons.hourglass_bottom : Icons.fiber_manual_record),
                      label: Text(_isRecording ? 'Recording...' : 'Start Trace'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isRecording ? Colors.grey : Colors.blueAccent,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _isRecording ? null : _startRecording,
                    ),
                  ),
                  
                  const Divider(height: 40),
                  
                  // Custom Event Injection Section
                  const Text('Live Injection', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _markerController,
                          decoration: const InputDecoration(
                            labelText: 'Marker Label',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.add_comment),
                        color: Colors.greenAccent,
                        onPressed: _injectCustomEvent,
                        tooltip: 'Inject Marker to Trace',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          // Right Panel: Logs
          Expanded(
            flex: 3,
            child: Container(
              color: const Color(0xFF1E1E1E),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Console Output', style: TextStyle(color: Colors.white70)),
                  const Divider(color: Colors.white24),
                  Expanded(
                    child: SingleChildScrollView(
                      reverse: true,
                      child: SelectableText(
                        _statusLog,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
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