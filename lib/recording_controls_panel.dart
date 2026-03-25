import 'dart:io';
import 'package:flutter/material.dart';
import 'l10n/app_localizations.dart';

/// A unified recording controls panel shared by [RecorderScreen] and
/// [CallStackScreen]. It renders:
///   - Elapsed / total timer + progress bar
///   - Start / Stop button
///   - Duration slider
///   - Output filename field (with auto-generate lock toggle)
///   - Buffer size field (with auto-calculate toggle)
///   - Open Explorer + Open Perfetto action buttons
///
/// This widget is purely presentational — all state is owned by the caller
/// and communicated via callbacks.
class RecordingControlsPanel extends StatelessWidget {
  const RecordingControlsPanel({
    super.key,
    required this.elapsedMs,
    required this.durationMs,
    required this.isRecording,
    required this.isButtonLocked,
    required this.durationSteps,
    required this.onDurationChanged,
    required this.outputFileController,
    required this.autoGenerateFilename,
    required this.onToggleAutoFilename,
    required this.bufferSizeController,
    required this.autoBufferSize,
    required this.onToggleAutoBuffer,
    required this.onStart,
    required this.onStop,
    required this.onOpenExplorer,
    required this.onOpenPerfetto,
    this.isProcessing = false,
    this.formatTimer,
    this.sliderLabel,
  });

  // ── Timer & Progress ─────────────────────────────────────────────────────
  final int elapsedMs;
  final double durationMs;
  final bool isRecording;

  // ── Button ───────────────────────────────────────────────────────────────
  final bool isButtonLocked;
  final VoidCallback onStart;
  final VoidCallback onStop;

  // ── Duration Slider ──────────────────────────────────────────────────────
  /// Discrete step values in milliseconds.
  final List<int> durationSteps;

  /// Called with the new [durationMs] value when the slider changes.
  final void Function(double newDurationMs) onDurationChanged;

  // ── Output Filename ──────────────────────────────────────────────────────
  final TextEditingController outputFileController;
  final bool autoGenerateFilename;
  final VoidCallback onToggleAutoFilename;

  // ── Buffer Size ───────────────────────────────────────────────────────────
  final TextEditingController bufferSizeController;
  final bool autoBufferSize;
  final VoidCallback onToggleAutoBuffer;

  // ── Action Buttons ────────────────────────────────────────────────────────
  final VoidCallback onOpenExplorer;
  final VoidCallback onOpenPerfetto;
  final bool isProcessing;

  // ── Optional overrides ────────────────────────────────────────────────────
  /// Override the timer display format. Defaults to `mm:ss.d`.
  final String Function(int ms)? formatTimer;

  /// Override the slider bubble label. Defaults to `{seconds}s`.
  final String Function(int ms)? sliderLabel;

  // ── Private helpers ───────────────────────────────────────────────────────

  String _defaultFormatTimer(int ms) {
    final d = Duration(milliseconds: ms);
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final ds = d.inMilliseconds % 1000 ~/ 100;
    return '$m:$s.$ds';
  }

  String _defaultSliderLabel(int ms) => '${(ms / 1000).toInt()}s';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final fmt = formatTimer ?? _defaultFormatTimer;
    final lblFn = sliderLabel ?? _defaultSliderLabel;

    final currentStepIndex = durationSteps.indexOf(durationMs.toInt());

    return Container(
      padding: const EdgeInsets.all(12),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Row: Timer + Start/Stop button ─────────────────────────────
          Row(
            children: [
              // Timer + progress bar
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Text(
                        '${fmt(elapsedMs)} / ${fmt(durationMs.toInt())} m:s',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: (durationMs > 0 && isRecording)
                          ? (elapsedMs / durationMs).clamp(0.0, 1.0)
                          : 0,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              // Start / Stop button
              Expanded(
                flex: 1,
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    icon: Icon(
                      isRecording ? Icons.stop_circle : Icons.radio_button_on,
                      size: 20,
                    ),
                    label: Text(
                      isRecording ? l10n.stop : l10n.start,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          isRecording ? Colors.redAccent : Colors.blueAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: isButtonLocked
                        ? null
                        : (isRecording ? onStop : onStart),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // ── Duration Slider ─────────────────────────────────────────────
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackShape: const RectangularSliderTrackShape(),
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            ),
            child: Row(
              children: [
                const Icon(Icons.timer_outlined, size: 18),
                Text(
                  '  ${l10n.maxDuration}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Expanded(
                  child: Slider(
                    value:
                        currentStepIndex >= 0 ? currentStepIndex.toDouble() : 0,
                    min: 0,
                    max: (durationSteps.length - 1).toDouble(),
                    divisions: durationSteps.length - 1,
                    label: lblFn(durationMs.toInt()),
                    onChanged: isRecording
                        ? null
                        : (v) => onDurationChanged(
                              durationSteps[v.toInt()].toDouble(),
                            ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // ── Output Filename ─────────────────────────────────────────────
          TextField(
            controller: outputFileController,
            readOnly: autoGenerateFilename,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              labelText: l10n.outputTraceFile,
              border: const OutlineInputBorder(),
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              prefixIcon: autoGenerateFilename
                  ? const Icon(Icons.file_open, size: 18)
                  : const Icon(Icons.edit_document, size: 18),
              suffixIcon: IconButton(
                iconSize: 16,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: autoGenerateFilename
                    ? const Icon(Icons.lock)
                    : const Icon(Icons.lock_open),
                onPressed: isRecording ? null : onToggleAutoFilename,
                tooltip: autoGenerateFilename
                    ? 'Unlock to edit'
                    : 'Lock to auto-generate',
              ),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),

          // ── Buffer Size + Action Buttons ────────────────────────────────
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Buffer size input
                SizedBox(
                  width: 120,
                  child: TextField(
                    textAlign: TextAlign.right,
                    controller: bufferSizeController,
                    readOnly: autoBufferSize,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      labelText: l10n.bufferSize,
                      isDense: true,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 12),
                      suffixText: 'MB',
                      suffixIconConstraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      suffixIcon: IconButton(
                        iconSize: 16,
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                        icon: autoBufferSize
                            ? const Icon(Icons.auto_fix_normal)
                            : const Icon(Icons.auto_fix_off),
                        onPressed: isRecording ? null : onToggleAutoBuffer,
                        tooltip: autoBufferSize
                            ? 'Unlock to edit'
                            : 'Lock to auto-calculate',
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Open Explorer
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: Text(
                      l10n.openExplorer,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    onPressed: (isRecording || isProcessing) ? null : onOpenExplorer,
                  ),
                ),
                const SizedBox(width: 8),
                // Open Perfetto
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.open_in_browser, size: 18),
                    label: Text(
                      l10n.openPerfetto,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    onPressed: (isRecording || isProcessing) ? null : onOpenPerfetto,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A helper that opens Windows Explorer at the given [filePath] if the file
/// exists, or at [fallbackDir] otherwise.
Future<void> openExplorer(String? filePath, Directory fallbackDir) async {
  if (!await fallbackDir.exists()) {
    await fallbackDir.create(recursive: true);
  }
  if (filePath != null && File(filePath).existsSync()) {
    await Process.start('explorer.exe', ['/select,', filePath]);
  } else {
    await Process.start('explorer.exe', [fallbackDir.path]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// Shared AppBar actions widget for ADB device selection.
///
/// Renders a [DropdownButton] listing [devices] with a phone icon in the
/// selected-item display, plus a refresh [IconButton].
///
/// Place this inside `AppBar.actions` via [AdbDeviceSelector.asActions]:
/// ```dart
/// AppBar(
///   actions: AdbDeviceSelector.asActions(
///     devices: _adbDevices,
///     selectedDevice: _selectedDevice,
///     onChanged: (v) => setState(() => _selectedDevice = v),
///     onRefresh: _refreshAdbDevices,
///   ),
/// )
/// ```
class AdbDeviceSelector extends StatelessWidget {
  const AdbDeviceSelector({
    super.key,
    required this.devices,
    required this.selectedDevice,
    required this.onChanged,
    required this.onRefresh,
  });

  final List<String> devices;
  final String? selectedDevice;
  final ValueChanged<String?> onChanged;
  final VoidCallback onRefresh;

  /// Convenience constructor — returns the two widgets ready to drop into
  /// `AppBar.actions`.
  static List<Widget> asActions({
    required List<String> devices,
    required String? selectedDevice,
    required ValueChanged<String?> onChanged,
    required VoidCallback onRefresh,
  }) {
    return [
      AdbDeviceSelector(
        devices: devices,
        selectedDevice: selectedDevice,
        onChanged: onChanged,
        onRefresh: onRefresh,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: selectedDevice,
            isDense: true,
            menuMaxHeight: 300,
            hint: Text(l10n.noDevice, style: const TextStyle(fontSize: 12)),
            selectedItemBuilder: (context) {
              return devices.map<Widget>((item) {
                return Row(
                  children: [
                    const Icon(Icons.phone_android, size: 12),
                    const SizedBox(width: 8),
                    Text(item, style: const TextStyle(fontSize: 12)),
                  ],
                );
              }).toList();
            },
            items: devices
                .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                .toList(),
            onChanged: onChanged,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: onRefresh,
          tooltip: l10n.refreshDevices,
        ),
      ],
    );
  }
}
