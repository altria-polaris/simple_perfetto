import 'dart:io';
import 'package:flutter/material.dart';
import 'l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'recorder.dart';
import 'callstack.dart';
import 'about.dart';
import 'settings.dart';

// Global Theme Notifiers
final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(ThemeMode.dark);
final ValueNotifier<Color> colorSeedNotifier = ValueNotifier(Colors.blueGrey);
final ValueNotifier<Locale?> localeNotifier = ValueNotifier(null);
final ValueNotifier<String> updateUrlNotifier = ValueNotifier('');

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

  // Load update URL
  updateUrlNotifier.value = prefs.getString('updateUrl') ?? '';

  // Add listeners to save changes
  themeModeNotifier.addListener(() => prefs.setString('themeMode', themeModeNotifier.value.name));
  colorSeedNotifier.addListener(() => prefs.setInt('colorSeed', colorSeedNotifier.value.toARGB32()));
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
  updateUrlNotifier.addListener(() => prefs.setString('updateUrl', updateUrlNotifier.value));

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

enum _NavPage {
  record,
  callStack,
  settings,
  about,
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  _NavPage _selectedPage = _NavPage.record;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final topNavPages = [_NavPage.record, _NavPage.callStack];

    return Scaffold(
      body: Row(
        children: [
          // Left side navigation rail
          Column(
            children: [
              Expanded(
                child: NavigationRail(
                  selectedIndex: topNavPages.contains(_selectedPage)
                      ? topNavPages.indexOf(_selectedPage)
                      : null,
                  onDestinationSelected: (int index) {
                    setState(() {
                      _selectedPage = topNavPages[index];
                    });
                  },
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    NavigationRailDestination(
                      icon: const Icon(Icons.fiber_manual_record_outlined),
                      selectedIcon: const Icon(Icons.fiber_manual_record),
                      label: Text(l10n.record),
                    ),
                    NavigationRailDestination(
                      icon: const Icon(Icons.stacked_bar_chart_outlined),
                      selectedIcon: const Icon(Icons.stacked_bar_chart),
                      label: Text(l10n.callStack),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildBottomNavItem(
                      context,
                      page: _NavPage.settings,
                      icon: Icons.settings_outlined,
                      selectedIcon: Icons.settings,
                      label: l10n.settings,
                    ),
                    const SizedBox(height: 16),
                    _buildBottomNavItem(
                      context,
                      page: _NavPage.about,
                      icon: Icons.person_outline,
                      selectedIcon: Icons.person,
                      label: l10n.about,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          // Right side content area
          Expanded(
            child: IndexedStack(
              index: _selectedPage.index,
              children: const [
                RecorderScreen(),
                CallStackScreen(),
                SettingsScreen(),
                AboutScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavItem(
    BuildContext context, {
    required _NavPage page,
    required IconData icon,
    required IconData selectedIcon,
    required String label,
  }) {
    final isSelected = _selectedPage == page;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          isSelected: isSelected,
          icon: Icon(icon),
          selectedIcon: Icon(selectedIcon),
          onPressed: () => setState(() => _selectedPage = page),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}