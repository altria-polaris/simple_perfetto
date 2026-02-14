import 'dart:io';
import 'package:flutter/material.dart';
import 'l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'recorder.dart';
import 'converter.dart';
import 'callstack.dart';
import 'about.dart';
import 'settings.dart';

// Global Theme Notifiers
final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(ThemeMode.dark);
final ValueNotifier<Color> colorSeedNotifier = ValueNotifier(Colors.blueGrey);
final ValueNotifier<Locale?> localeNotifier = ValueNotifier(null);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  // Load ThemeMode
  final themeModeName = prefs.getString('themeMode') ?? ThemeMode.dark.name;
  themeModeNotifier.value = ThemeMode.values.firstWhere((e) => e.name == themeModeName, orElse: () => ThemeMode.dark);

  // Load ColorSeed
  final colorValue = prefs.getInt('colorSeed') ?? Colors.blueGrey.value;
  colorSeedNotifier.value = Color(colorValue);

  // Load Locale
  final languageCode = prefs.getString('languageCode');
  if (languageCode != null) {
    final countryCode = prefs.getString('countryCode');
    localeNotifier.value = Locale(languageCode, countryCode);
  }

  // Add listeners to save changes
  themeModeNotifier.addListener(() => prefs.setString('themeMode', themeModeNotifier.value.name));
  colorSeedNotifier.addListener(() => prefs.setInt('colorSeed', colorSeedNotifier.value.value));
  localeNotifier.addListener(() async {
    final prefs = await SharedPreferences.getInstance();
    final locale = localeNotifier.value;
    if (locale == null) {
      await prefs.remove('languageCode');
      await prefs.remove('countryCode');
    } else {
      await prefs.setString('languageCode', locale.languageCode);
      if (locale.countryCode != null) {
        await prefs.setString('countryCode', locale.countryCode!);
      } else {
        await prefs.remove('countryCode');
      }
    }
  });

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    await windowManager.setSize(const Size(600, 600));
    await windowManager.setAlignment(Alignment.center);
    await windowManager.setResizable(false);
    await windowManager.show();
  }
  runApp(const PerfettoRecorderApp());
}

class PerfettoRecorderApp extends StatelessWidget {
  const PerfettoRecorderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, themeMode, _) {
        return ValueListenableBuilder<Color>(
          valueListenable: colorSeedNotifier,
          builder: (context, colorSeed, _) {
            return ValueListenableBuilder<Locale?>(
              valueListenable: localeNotifier,
              builder: (context, locale, _) {
                return MaterialApp(
                  title: 'Perfetto UI Recorder',
                  theme: ThemeData(
                    colorSchemeSeed: colorSeed,
                    brightness: Brightness.light,
                    useMaterial3: true,
                  ),
                  darkTheme: ThemeData(
                    colorSchemeSeed: colorSeed,
                    brightness: Brightness.dark,
                    useMaterial3: true,
                  ),
                  themeMode: themeMode,
                  locale: locale,
                  localizationsDelegates: AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  builder: (context, child) {
                    final l10n = AppLocalizations.of(context);
                    return Theme(
                      data: Theme.of(context).copyWith(
                        textTheme: Theme.of(context).textTheme.apply(fontFamily: l10n?.fontFamily),
                      ),
                      child: child!,
                    );
                  },
                  home: const MainScreen(),
                );
              },
            );
          },
        );
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  // Define the pages for each section
  final List<Widget> _pages = const [
    RecorderScreen(),
    CallStackScreen(),
    TraceConverterScreen(),
    SettingsScreen(),
    AboutScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: Row(
        children: [
          // Left side navigation rail
          Column(
            children: [
              Expanded(
                child: NavigationRail(
                  selectedIndex: _selectedIndex < 3 ? _selectedIndex : null,
                  onDestinationSelected: (int index) {
                    setState(() {
                      _selectedIndex = index;
                    });
                  },
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    NavigationRailDestination(
                      icon: Icon(Icons.fiber_manual_record_outlined),
                      selectedIcon: Icon(Icons.fiber_manual_record),
                      label: Text(l10n.record),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.stacked_bar_chart_outlined),
                      selectedIcon: Icon(Icons.stacked_bar_chart),
                      label: Text(l10n.callStack),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.transform_outlined),
                      selectedIcon: Icon(Icons.transform),
                      label: Text(l10n.convert),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      isSelected: _selectedIndex == 3,
                      icon: const Icon(Icons.settings_outlined),
                      selectedIcon: const Icon(Icons.settings),
                      onPressed: () => setState(() => _selectedIndex = 3),
                    ),
                    Text(l10n.settings, style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 16),
                    IconButton(
                      isSelected: _selectedIndex == 4,
                      icon: const Icon(Icons.person_outline),
                      selectedIcon: const Icon(Icons.person),
                      onPressed: () => setState(() => _selectedIndex = 4),
                    ),
                    Text(l10n.about, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          // Right side content area
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: _pages,
            ),
          ),
        ],
      ),
    );
  }
}