import 'dart:io';
import 'package:flutter/material.dart';

class TargetAppInput extends StatelessWidget {
  final TextEditingController controller;
  final String labelText;
  final String hintText;
  final IconData prefixIcon;
  final String? selectedDevice;
  final void Function(String)? onMessage;

  const TargetAppInput({
    super.key,
    required this.controller,
    required this.labelText,
    this.hintText = 'e.g. com.android.settings',
    this.prefixIcon = Icons.search,
    this.selectedDevice,
    this.onMessage,
  });

  Future<void> _fetchTopApp() async {
    final deviceArgs =
        selectedDevice != null ? ['-s', selectedDevice!] : <String>[];
    onMessage?.call('Fetching top app...');
    try {
      final result =
          await Process.run('adb', [...deviceArgs, 'shell', 'dumpsys window']);
      final out = result.stdout.toString();
      final lines = out.split('\n');
      String? topPkg;

      final focusRegExp = RegExp(r'mCurrentFocus=.*?\s+([a-zA-Z0-9_.-]+)/');

      for (final line in lines) {
        if (line.contains('mCurrentFocus=')) {
          final match = focusRegExp.firstMatch(line);
          if (match != null && match.group(1) != 'null') {
            topPkg = match.group(1);
            break;
          }
        }
      }

      if (topPkg != null) {
        if (controller.text.isEmpty) {
          controller.text = topPkg;
        } else if (!controller.text.contains(topPkg)) {
          controller.text += ', $topPkg';
        }
        onMessage?.call('Added $topPkg');
      } else {
        onMessage?.call('Could not determine top app');
      }
    } catch (e) {
      onMessage?.call('Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        border: const OutlineInputBorder(),
        prefixIcon: Icon(prefixIcon, size: 18),
        suffixIcon: Tooltip(
          message: "Get foreground app name",
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: _fetchTopApp,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: const [
                  Icon(Icons.add_to_home_screen, size: 16),
                  SizedBox(width: 4),
                  Text("get top APP", style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
        isDense: true,
      ),
    );
  }
}
