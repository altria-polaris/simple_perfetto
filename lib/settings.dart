import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import 'l10n/app_localizations.dart';
import 'main.dart';

// Todo: replace this with your actual Windows shared folder path
const String _kUpdateUrl = r'D:\workspace\updater';  // or shared path like r'\\server\share\updates

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settings),
      ),
      body: Padding(
        padding: const EdgeInsets.only(left: 12, right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionTitle(title: l10n.appearance),
            const _AppearanceCard(),
            const SizedBox(height: 8),
            _SectionTitle(title: l10n.colorScheme),
            const _ColorSeedCard(),
            const SizedBox(height: 8),
            _SectionTitle(title: l10n.updates),
            const _UpdateSettingsCard(),
            const SizedBox(height: 8),
            _SectionTitle(title: l10n.actions),
            const _ActionsCard(),
          ]),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.only(left: 12, right: 12, top: 8, bottom: 8),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.brightness_6),
                const SizedBox(width: 16),
                Expanded(child: Text(l10n.themeMode)),
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: themeModeNotifier,
                  builder: (context, mode, _) {
                    return DropdownButton<ThemeMode>(
                      value: mode,
                      underline: const SizedBox(),
                      onChanged: (ThemeMode? newMode) {
                        if (newMode != null) themeModeNotifier.value = newMode;
                      },
                      items: [
                        DropdownMenuItem(value: ThemeMode.system, child: Text(l10n.themeModeSystem)),
                        DropdownMenuItem(value: ThemeMode.light, child: Text(l10n.themeModeLight)),
                        DropdownMenuItem(value: ThemeMode.dark, child: Text(l10n.themeModeDark)),
                      ],
                    );
                  },
                ),
              ],
            ),
            const Divider(height: 12),
            Row(
              children: [
                const Icon(Icons.language),
                const SizedBox(width: 16),
                Expanded(child: Text(l10n.language)),
                ValueListenableBuilder<Locale?>(
                  valueListenable: localeNotifier,
                  builder: (context, locale, _) {
                    final availableItems = <Locale?>[
                      null,
                      const Locale('en'),
                      const Locale('zh', 'TW'),
                      const Locale('zh', 'CN')
                    ];
                    final dropdownValue = availableItems.contains(locale) ? locale : null;

                    return DropdownButton<Locale?>(
                      value: dropdownValue,
                      underline: const SizedBox(),
                      hint: Text(l10n.systemDefault),
                      onChanged: (Locale? newLocale) {
                        localeNotifier.value = newLocale;
                      },
                      items: availableItems.map((l) {
                        return DropdownMenuItem(
                          value: l,
                          child: Text(_getLocaleName(l, l10n)),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getLocaleName(Locale? locale, AppLocalizations l10n) {
    if (locale == null) return l10n.systemDefault;
    switch (locale.languageCode) {
      case 'en':
        return l10n.english;
      case 'zh':
        return locale.countryCode == 'TW' ? l10n.traditionalChinese : l10n.simplifiedChinese;
      default:
        return locale.toLanguageTag();
    }
  }
}

class _ColorSeedCard extends StatelessWidget {
  const _ColorSeedCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ValueListenableBuilder<Color>(
          valueListenable: colorSeedNotifier,
          builder: (context, currentColor, _) {
            final List<Color> colors = [
              Colors.indigo,
              Colors.blue,
              Colors.orange,
              Colors.green,
              Colors.brown,
            ];
            return Wrap(
              spacing: 40,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: colors.map((color) {
                final isSelected = currentColor == color;
                return GestureDetector(
                  onTap: () => colorSeedNotifier.value = color,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: isSelected
                          ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 3)
                          : null,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(50),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 24) : null,
                  ),
                );
              }).toList(),
            );
          },
        ),
      ),
    );
  }
}

class _ActionsCard extends StatelessWidget {
  const _ActionsCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Center(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.refresh),
            label: Text(l10n.resetToDefaults),
            onPressed: () => _showResetConfirmationDialog(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
              side: BorderSide(color: Theme.of(context).colorScheme.error.withAlpha(128)),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showResetConfirmationDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(l10n.resetSettingsConfirmationTitle),
          content: Text(l10n.resetSettingsConfirmationContent),
          actions: <Widget>[
            TextButton(
              child: Text(l10n.cancel),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            TextButton(
              child: Text(l10n.reset, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              onPressed: () {
                themeModeNotifier.value = ThemeMode.light;
                colorSeedNotifier.value = Colors.blueGrey;
                localeNotifier.value = null;
                updateUrlNotifier.value = '';
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        );
      },
    );
  }
}

class _UpdateSettingsCard extends StatefulWidget {
  const _UpdateSettingsCard();

  @override
  _UpdateSettingsCardState createState() => _UpdateSettingsCardState();
}

class _UpdateSettingsCardState extends State<_UpdateSettingsCard> {
  bool _isCheckingForUpdate = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _currentVersion = '';

  @override
  void initState() {
    super.initState();
    _initPackageInfo();
  }

  Future<void> _initPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _currentVersion = 'v${info.version}+${info.buildNumber}';
      });
    }
  }

  Future<void> _checkForUpdates() async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final updatePath = _kUpdateUrl;

    if (updatePath.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.updateUrlHint)));
      return;
    }

    setState(() => _isCheckingForUpdate = true);

    try {
      final versionJsonPath = '$updatePath${Platform.pathSeparator}version.json';
      final versionFile = File(versionJsonPath);

      if (!await versionFile.exists()) {
        throw Exception('version.json not found in the specified directory.');
      }

      final versionContent = await versionFile.readAsString();
      final versionInfo = jsonDecode(versionContent);

      final newVersion = versionInfo['version'];
      final newBuild = versionInfo['build'];
      final newVersionString = 'v$newVersion+$newBuild';

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersionString = 'v${packageInfo.version}+${packageInfo.buildNumber}';

      if (!mounted) return;

      if (newVersionString != currentVersionString) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.updateAvailable),
            content: Text('New version $newVersionString is available. Current version is $currentVersionString.'),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.cancel)),
              TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l10n.downloading)),
            ],
          ),
        );

        if (confirmed == true) {
          await _downloadAndInstallUpdate(versionInfo);
        }
      } else {
        messenger.showSnackBar(SnackBar(content: Text(l10n.upToDate)));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('${l10n.errorCheckingUpdate}: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isCheckingForUpdate = false);
      }
    }
  }

  Future<void> _downloadAndInstallUpdate(Map<String, dynamic> versionInfo) async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final updatePath = _kUpdateUrl;

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });

    try {
      final zipPath = '$updatePath${Platform.pathSeparator}${versionInfo['path']}';
      final zipFile = File(zipPath);

      if (!await zipFile.exists()) {
        throw Exception('Update file not found: ${versionInfo['path']}');
      }

      final tempDir = await getTemporaryDirectory();

      // Copy file locally to show progress, then unzip from local copy.
      final localZipFile = File('${tempDir.path}${Platform.pathSeparator}update.zip');
      if (await localZipFile.exists()) {
        await localZipFile.delete();
      }

      final sink = localZipFile.openWrite();
      final fileStream = zipFile.openRead();
      final totalBytes = await zipFile.length();
      int copiedBytes = 0;

      await for (final chunk in fileStream) {
        sink.add(chunk);
        copiedBytes += chunk.length;
        if (mounted) {
          setState(() {
            _downloadProgress = totalBytes > 0 ? copiedBytes / totalBytes : 0.0;
          });
        }
      }
      await sink.close();

      if (!mounted) return;
      setState(() => _isDownloading = false);

      final extractPath = '${tempDir.path}${Platform.pathSeparator}update';
      // Ensure the target directory is clean before extraction.
      final extractDir = Directory(extractPath);
      if (await extractDir.exists()) {
        await extractDir.delete(recursive: true);
      }

      // Use the helper from archive_io to extract directly from the file.
      // This is more memory-efficient and the code is cleaner.
      await extractFileToDisk(localZipFile.path, extractPath);

      // Validate the update content to prevent breaking the installation.
      // The zip file must contain the executable at the root level.
      final executableName = Platform.resolvedExecutable.split(Platform.pathSeparator).last;
      final updateExe = File('$extractPath${Platform.pathSeparator}$executableName');
      
      if (!await updateExe.exists()) {
        throw Exception('Invalid update package: $executableName not found. Please ensure you zipped the *files*, not the folder.');
      }

      await localZipFile.delete(); // Clean up the copied zip

      if (!mounted) return;

      if (Platform.isWindows) {
        final installPath = Directory(Platform.resolvedExecutable).parent.path;
        final currentPid = pid;

        final scriptContent = """
@echo off
setlocal
echo Waiting for application (PID: $currentPid) to close...
:waitloop
tasklist /FI "PID eq $currentPid" | find "$currentPid" > nul
if not errorlevel 1 (
    timeout /t 1 /nobreak > nul
    goto waitloop
)

echo Application closed.
timeout /t 2 /nobreak > nul
echo Replacing application files...
robocopy "$extractPath" "$installPath" /E /IS /IT /NFL /NDL /NJH /NJS /nc /ns /np /R:10 /W:1
if errorlevel 8 (
  echo Robocopy failed with error code %errorlevel%. Halting update.
  pause
  exit /b %errorlevel%
)

echo Relaunching application...
timeout /t 2 /nobreak > nul
explorer.exe "$installPath\\$executableName"

echo Cleaning up...
rmdir /S /Q "$extractPath"
echo Update complete. Press any key to close this window.
(goto) 2>nul & del "%~f0" & pause & exit
""";
        final scriptFile = File('${tempDir.path}\\update.bat');
        await scriptFile.writeAsString(scriptContent);

        // Use Process.start in detached mode to launch the update script
        // in a separate process and not wait for it. This allows the main
        // app to exit immediately.
        await Process.start('cmd', ['/c', 'start', '""', scriptFile.path],
            runInShell: true, mode: ProcessStartMode.detached);
        exit(0);
      } else {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.installAndRestart),
            content: Text(
                'Update has been prepared. Please close the app, replace files from "$updatePath", and restart.'),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Failed to perform update: $e')));
        setState(() => _isDownloading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            if (_currentVersion.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  '${l10n.version} $_currentVersion',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            if (_isDownloading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Column(
                  children: [
                    LinearProgressIndicator(value: _downloadProgress),
                    const SizedBox(height: 4),
                    Text('${(_downloadProgress * 100).toStringAsFixed(0)}%'),
                  ],
                ),
              )
            else
              ElevatedButton.icon(
                icon: const Icon(Icons.update),
                label: Text(l10n.checkForUpdates),
                onPressed: _isCheckingForUpdate ? null : _checkForUpdates,
              ),
          ],
        ),
      ),
    );
  }
}
