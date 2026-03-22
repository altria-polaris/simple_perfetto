// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get settings => 'Settings';

  @override
  String get appearance => 'Appearance';

  @override
  String get themeMode => 'Theme Mode';

  @override
  String get language => 'Language';

  @override
  String get colorScheme => 'Color Scheme';

  @override
  String get actions => 'Actions';

  @override
  String get resetToDefaults => 'Reset to Defaults';

  @override
  String get record => 'Record';

  @override
  String get callStack => 'CallStack';

  @override
  String get convert => 'Convert';

  @override
  String get about => 'About';

  @override
  String get systemDefault => 'System Default';

  @override
  String get english => 'English';

  @override
  String get traditionalChinese => '繁體中文';

  @override
  String get simplifiedChinese => '简体中文';

  @override
  String get themeModeSystem => 'System Default';

  @override
  String get themeModeLight => 'Light';

  @override
  String get themeModeDark => 'Dark';

  @override
  String get resetSettingsConfirmationTitle => 'Reset Settings?';

  @override
  String get resetSettingsConfirmationContent => 'This will reset all appearance settings to their default values. This action cannot be undone.';

  @override
  String get cancel => 'Dismiss';

  @override
  String get reset => 'Reset';

  @override
  String get appTitle => 'Simple Perfetto Recorder';

  @override
  String get noDevice => 'No Device';

  @override
  String get refreshDevices => 'Refresh Devices';

  @override
  String get start => 'START';

  @override
  String get stop => 'STOP';

  @override
  String get maxDuration => 'Max Duration';

  @override
  String get bufferSize => 'Buffer Size';

  @override
  String get outputTraceFile => 'Output Trace File';

  @override
  String get openExplorer => 'Open Explorer';

  @override
  String get openPerfetto => 'Open Perfetto';

  @override
  String get fontFamily => 'Roboto';

  @override
  String get updates => 'Updates';

  @override
  String get checkForUpdates => 'Check for Updates';

  @override
  String get updateAvailable => 'Update Available';

  @override
  String get upToDate => 'App is up to date';

  @override
  String get download => 'Download Update';

  @override
  String get installAndRestart => 'Install & Restart';

  @override
  String get errorCheckingUpdate => 'Error checking for update';

  @override
  String get version => 'Version';

  @override
  String get recordingInProgress => 'Recording in progress...';

  @override
  String get startingPerfetto => 'Starting Perfetto...';

  @override
  String get startingCallstack => 'Starting Perfetto (Callstack)...';

  @override
  String get recordingFinishedPulling => 'Recording finished. Pulling trace...';

  @override
  String get stoppingManually => 'Stopping manually...';

  @override
  String successSavedTo(Object path) {
    return 'Success! Saved to $path';
  }

  @override
  String pullFailed(Object error) {
    return 'Pull failed: $error';
  }

  @override
  String errorStartingProcess(Object error) {
    return 'Error starting process: $error';
  }

  @override
  String perfettoError(Object code) {
    return 'Error: Perfetto exited with code $code';
  }

  @override
  String errorPullingFile(Object error) {
    return 'Error pulling file: $error';
  }

  @override
  String errorGettingDevices(Object error) {
    return 'Error getting devices: $error';
  }

  @override
  String ftraceFormatError(Object token) {
    return 'Error: Ftrace event \"$token\" must be in \"category/event\" format.';
  }

  @override
  String fileNotFound(Object filename) {
    return 'File not found: $filename';
  }

  @override
  String get servingTrace => 'Serving trace on port 9001...';

  @override
  String errorStartingServer(Object error) {
    return 'Error starting server: $error';
  }

  @override
  String get fetchingTopApp => 'Fetching top app...';

  @override
  String addedApp(Object app) {
    return 'Added $app';
  }

  @override
  String get couldNotDetermineTopApp => 'Could not determine top app';

  @override
  String genericError(Object error) {
    return 'Error: $error';
  }

  @override
  String get manualEditsHint => 'Manual edits here will be used for the next recording.';

  @override
  String get goToSettings => 'Go to Settings';
}
