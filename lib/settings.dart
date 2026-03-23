import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import 'l10n/app_localizations.dart';
import 'main.dart';

// Todo: replace this with your actual Windows shared folder path
const String _kUpdateUrl =
    r'D:\workspace\simple_perfetto\test_update'; // Test update directory

bool _isNewerVersion(String newVersion, String newBuild, String currentVersion,
    String currentBuild) {
  List<int> parseVersion(String v) =>
      v.split('.').map((e) => int.tryParse(e) ?? 0).toList();

  final newParts = parseVersion(newVersion);
  final currParts = parseVersion(currentVersion);

  final maxLength =
      newParts.length > currParts.length ? newParts.length : currParts.length;

  for (int i = 0; i < maxLength; i++) {
    final n = i < newParts.length ? newParts[i] : 0;
    final c = i < currParts.length ? currParts[i] : 0;
    if (n > c) return true;
    if (n < c) return false;
  }

  final nBuild = int.tryParse(newBuild) ?? 0;
  final cBuild = int.tryParse(currentBuild) ?? 0;
  return nBuild > cBuild;
}

Future<Map<String, dynamic>?> checkUpdateSilent() async {
  try {
    if (_kUpdateUrl.isEmpty) return null;
    final versionFile =
        File('$_kUpdateUrl${Platform.pathSeparator}version.json');
    if (!await versionFile.exists()) return null;

    final versionContent = await versionFile.readAsString();
    final versionInfo = jsonDecode(versionContent);

    final newVersion = versionInfo['version'];
    final newBuild = versionInfo['build'];

    final packageInfo = await PackageInfo.fromPlatform();

    if (_isNewerVersion(
        newVersion, newBuild, packageInfo.version, packageInfo.buildNumber)) {
      return versionInfo;
    }
  } catch (_) {}
  return null;
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: Padding(
        padding: const EdgeInsets.only(left: 12, right: 12),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
                        DropdownMenuItem(
                            value: ThemeMode.system,
                            child: Text(l10n.themeModeSystem)),
                        DropdownMenuItem(
                            value: ThemeMode.light,
                            child: Text(l10n.themeModeLight)),
                        DropdownMenuItem(
                            value: ThemeMode.dark,
                            child: Text(l10n.themeModeDark)),
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
                    final dropdownValue =
                        availableItems.contains(locale) ? locale : null;

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
        return locale.countryCode == 'TW'
            ? l10n.traditionalChinese
            : l10n.simplifiedChinese;
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
                          ? Border.all(
                              color: Theme.of(context).colorScheme.onSurface,
                              width: 3)
                          : null,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(50),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 24)
                        : null,
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
              side: BorderSide(
                  color: Theme.of(context).colorScheme.error.withAlpha(128)),
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
              child: Text(l10n.reset,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
      messenger.showSnackBar(SnackBar(content: Text(_kUpdateUrl)));
      return;
    }

    setState(() => _isCheckingForUpdate = true);

    try {
      final versionJsonPath =
          '$updatePath${Platform.pathSeparator}version.json';
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
      final currentVersionString =
          'v${packageInfo.version}+${packageInfo.buildNumber}';

      if (!mounted) return;

      if (_isNewerVersion(
          newVersion, newBuild, packageInfo.version, packageInfo.buildNumber)) {
        final changesList = versionInfo['changes'] as List<dynamic>?;
        Widget? changesWidget;
        if (changesList != null && changesList.isNotEmpty) {
          changesWidget = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              const Text("What's New:",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              ...changesList.map((c) => Text('• $c')),
            ],
          );
        }

        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) => _UpdateDialog(
            versionInfo: versionInfo,
            newVersionString: newVersionString,
            currentVersionString: currentVersionString,
            changesWidget: changesWidget,
          ),
        );
      } else {
        messenger.showSnackBar(SnackBar(
          content: Text(l10n.upToDate),
          duration: const Duration(seconds: 1),
        ));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
            SnackBar(content: Text('${l10n.errorCheckingUpdate}: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isCheckingForUpdate = false);
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

class _UpdateDialog extends StatefulWidget {
  final Map<String, dynamic> versionInfo;
  final String newVersionString;
  final String currentVersionString;
  final Widget? changesWidget;

  const _UpdateDialog({
    required this.versionInfo,
    required this.newVersionString,
    required this.currentVersionString,
    this.changesWidget,
  });

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _statusMessage = '';

  Future<void> _downloadAndInstallUpdate() async {
    final l10n = AppLocalizations.of(context)!;
    final updatePath = _kUpdateUrl;

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _statusMessage = l10n.downloadingUpdate;
    });

    try {
      final zipPath =
          '$updatePath${Platform.pathSeparator}${widget.versionInfo['path']}';
      final zipFile = File(zipPath);

      if (!await zipFile.exists()) {
        throw Exception('Update file not found: ${widget.versionInfo['path']}');
      }

      final tempDir = await getTemporaryDirectory();

      final localZipFile =
          File('${tempDir.path}${Platform.pathSeparator}update.zip');
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
      setState(() {
        _statusMessage = l10n.extractingUpdate;
        _downloadProgress = -1.0;
      });

      final extractPath = '${tempDir.path}${Platform.pathSeparator}update';
      final extractDir = Directory(extractPath);
      if (await extractDir.exists()) {
        await extractDir.delete(recursive: true);
      }

      await extractFileToDisk(localZipFile.path, extractPath);

      final executableName =
          Platform.resolvedExecutable.split(Platform.pathSeparator).last;
      final updateExe =
          File('$extractPath${Platform.pathSeparator}$executableName');

      if (!await updateExe.exists()) {
        throw Exception('Invalid update package: $executableName not found.');
      }

      await localZipFile.delete();

      if (!mounted) return;
      setState(() {
        _statusMessage = l10n.readyToUpdate;
        _downloadProgress = 1.0;
      });
      await Future.delayed(const Duration(seconds: 1));

      if (!mounted) return;

      if (Platform.isWindows) {
        final installPath = Directory(Platform.resolvedExecutable).parent.path;
        final currentPid = pid;

        final scriptContent = """
@echo off
chcp 65001 > nul
setlocal
echo Update in progress. Please do not turn off this console window...
echo 更新進行中。請勿關閉此主控台視窗...
echo.
echo Waiting for application (PID: $currentPid) to close...
echo 等待應用程式 (PID: $currentPid) 關閉...

:waitloop
tasklist /FI "PID eq $currentPid" | find "$currentPid" > nul
if not errorlevel 1 (
    timeout /t 3 /nobreak > nul
    taskkill /F /PID $currentPid > nul 2>&1
    goto waitloop
)

echo.
echo Application closed.
echo 應用程式已關閉。
timeout /t 1 /nobreak > nul
echo.
echo Start to Update. Please do not turn off this console window...
echo 開始更新。請勿關閉此主控台視窗...
echo.
echo Replacing application files...
echo 正在替換應用程式檔案...
robocopy "$extractPath" "$installPath" /E /IS /IT /NFL /NDL /NJH /NJS /nc /ns /np /R:10 /W:1
if errorlevel 8 (
  echo Robocopy failed with error code %errorlevel%. Halting update.
  echo Robocopy 失敗，錯誤代碼 %errorlevel%。停止更新。
  pause
  exit /b %errorlevel%
)

echo Relaunching application...
echo 正在重新啟動應用程式...
timeout /t 2 /nobreak > nul
explorer.exe "$installPath\\$executableName"
echo.

echo Cleaning up...
echo 正在清理...
rmdir /S /Q "$extractPath"
echo Update complete.
echo 更新完成。
echo Press wait App relaunch and press any key to close this window.
echo 請稍等應用程式重新啟動後按任意鍵關閉此視窗。
(goto) 2>nul & del "%~f0" & pause & exit
""";
        final scriptFile = File('${tempDir.path}\\update.bat');
        await scriptFile.writeAsString(
            scriptContent.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n'));
        await Process.run('cmd', ['/c', 'start', scriptFile.path],
            runInShell: true);
        exit(0);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _statusMessage = 'Failed to perform update: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.updateAvailable),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: MediaQuery.of(context).size.width * 0.75,
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'New version ${widget.newVersionString} is available.\nCurrent version is ${widget.currentVersionString}.'),
              if (widget.changesWidget != null) widget.changesWidget!,
              if (_isDownloading || _statusMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_statusMessage,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      if (_isDownloading) ...[
                        const SizedBox(height: 8),
                        if (_downloadProgress >= 0.0)
                          LinearProgressIndicator(value: _downloadProgress)
                        else
                          const LinearProgressIndicator(),
                        if (_downloadProgress >= 0.0 && _downloadProgress < 1.0)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(
                                '${(_downloadProgress * 100).toStringAsFixed(0)}%'),
                          ),
                      ]
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (!_isDownloading) ...[
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel)),
          TextButton(
              onPressed: _downloadAndInstallUpdate, child: Text(l10n.download)),
        ] else ...[
          TextButton(
              onPressed: null,
              child: Text(l10n.download)), // Disabled while downloading
        ]
      ],
    );
  }
}
