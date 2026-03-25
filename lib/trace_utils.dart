import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';

class TraceUtils {
  /// Refreshes the list of ADB devices and determines the newly selected device.
  static Future<void> refreshAdbDevices({
    required String? currentDevice,
    required void Function(List<String> devices, String? selectedDevice)
        onSuccess,
    required void Function(String error) onError,
  }) async {
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
        String? newSelected = currentDevice;
        if (newSelected == null || !devices.contains(newSelected)) {
          newSelected = devices.isNotEmpty ? devices.first : null;
        }
        onSuccess(devices, newSelected);
      }
    } catch (e) {
      onError(e.toString());
    }
  }

  /// Pulls a generated trace file from the target device to the local Traces directory.
  static Future<void> pullTraceFile({
    required BuildContext context,
    required String traceName,
    required String? selectedDevice,
    required void Function(String message) updateStatus,
  }) async {
    try {
      final tracesDir = Directory('${Directory.current.path}\\Traces');
      if (!await tracesDir.exists()) {
        await tracesDir.create(recursive: true);
      }
      final localPath = '${tracesDir.path}\\$traceName';

      final deviceArgs =
          selectedDevice != null ? ['-s', selectedDevice] : <String>[];
      final result = await Process.run('adb', [
        ...deviceArgs,
        'pull',
        '/data/misc/perfetto-traces/$traceName',
        localPath
      ]);

      if (!context.mounted) return;
      final l10n = AppLocalizations.of(context)!;
      if (result.exitCode == 0) {
        updateStatus(l10n.successSavedTo(localPath));
      } else {
        updateStatus(l10n.pullFailed(result.stderr.toString()));
      }
    } catch (e) {
      if (!context.mounted) return;
      updateStatus(
          AppLocalizations.of(context)!.errorPullingFile(e.toString()));
    }
  }

  /// Starts a local HTTP server and opens the trace in Perfetto UI.
  /// Returns the newly bound HttpServer so the caller can close it later.
  static Future<HttpServer?> openTraceInBrowser({
    required BuildContext context,
    required String fileName,
    required HttpServer? existingServer,
    required void Function(String message) updateStatus,
  }) async {
    final tracesDir = Directory('${Directory.current.path}\\Traces');
    final filePath = '${tracesDir.path}\\$fileName';
    final l10n = AppLocalizations.of(context)!;

    if (!File(filePath).existsSync()) {
      updateStatus(l10n.fileNotFound(fileName));
      return existingServer;
    }

    await existingServer?.close(force: true);
    HttpServer? newServer;

    try {
      int port = 9001;
      for (int p = 9001; p <= 9020; p++) {
        try {
          newServer = await HttpServer.bind(InternetAddress.loopbackIPv4, p);
          port = p;
          break;
        } catch (_) {
          continue;
        }
      }

      if (newServer == null) {
        throw Exception(
            'Could not bind to any port from 9001 to 9020. Port may be in use.');
      }

      final encodedName = Uri.encodeComponent(fileName);

      newServer.listen((HttpRequest request) async {
        request.response.headers
            .add('Access-Control-Allow-Origin', 'https://ui.perfetto.dev');
        request.response.headers
            .add('Access-Control-Allow-Methods', 'GET, OPTIONS');
        request.response.headers.add('Access-Control-Allow-Headers', '*');
        request.response.headers.add('Cache-Control', 'no-cache');

        if (request.method == 'OPTIONS') {
          request.response.statusCode = HttpStatus.ok;
          await request.response.close();
          return;
        }

        if (request.uri.path == '/$encodedName') {
          final file = File(filePath);
          await file.openRead().pipe(request.response);
        } else {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        }
      });

      final url =
          'https://ui.perfetto.dev/#!/?url=http://127.0.0.1:$port/$encodedName&referrer=record_android_trace';

      Process.run('cmd', ['/c', 'start', url]);
      updateStatus(l10n.servingTrace);
      return newServer;
    } catch (e) {
      updateStatus(l10n.errorStartingServer(e.toString()));
      return null;
    }
  }

  /// Generates a randomized timestamped filename into the given controller.
  static void generateNewFilename({
    required String prefix,
    required TextEditingController controller,
  }) {
    final now = DateTime.now();
    final random = Random();
    final hex = random
        .nextInt(0x10000)
        .toRadixString(16)
        .toLowerCase()
        .padLeft(4, '0');
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final pfx = prefix.isNotEmpty ? '${prefix}_' : '';
    final fileName =
        '$pfx${now.year}-${twoDigits(now.month)}-${twoDigits(now.day)}_${twoDigits(now.hour)}-${twoDigits(now.minute)}_$hex.pftrace';
    controller.text = fileName;
  }

  /// Forcefully stops the recording process on the Android device via adb killall.
  static Future<void> stopPerfetto(String? selectedDevice) async {
    final deviceArgs =
        selectedDevice != null ? ['-s', selectedDevice] : <String>[];
    await Process.run('adb', [...deviceArgs, 'shell', 'killall', '-2', 'perfetto']);
  }
}
