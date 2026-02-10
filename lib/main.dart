import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'recorder.dart';
import 'converter.dart';
import 'callstack.dart';
import 'about.dart';
import 'settings.dart';

// Global Theme Notifiers
final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(ThemeMode.dark);
final ValueNotifier<Color> colorSeedNotifier = ValueNotifier(Colors.blueGrey);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
              home: const MainScreen(),
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
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.fiber_manual_record_outlined),
                      selectedIcon: Icon(Icons.fiber_manual_record),
                      label: Text('Record'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.stacked_bar_chart_outlined),
                      selectedIcon: Icon(Icons.stacked_bar_chart),
                      label: Text('Call Stack'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.transform_outlined),
                      selectedIcon: Icon(Icons.transform),
                      label: Text('Convert'),
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
                    const Text('Settings', style: TextStyle(fontSize: 12)),
                    const SizedBox(height: 16),
                    IconButton(
                      isSelected: _selectedIndex == 4,
                      icon: const Icon(Icons.person_outline),
                      selectedIcon: const Icon(Icons.person),
                      onPressed: () => setState(() => _selectedIndex = 4),
                    ),
                    const Text('About', style: TextStyle(fontSize: 12)),
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