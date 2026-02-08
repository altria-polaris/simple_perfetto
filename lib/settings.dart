import 'package:flutter/material.dart';
import 'main.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _buildSectionTitle(context, 'Appearance'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.brightness_6),
                      const SizedBox(width: 16),
                      const Expanded(child: Text('Theme Mode')),
                      ValueListenableBuilder<ThemeMode>(
                        valueListenable: themeModeNotifier,
                        builder: (context, mode, _) {
                          return DropdownButton<ThemeMode>(
                            value: mode,
                            underline: const SizedBox(),
                            onChanged: (ThemeMode? newMode) {
                              if (newMode != null) {
                                themeModeNotifier.value = newMode;
                              }
                            },
                            items: const [
                              DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
                              DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                              DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionTitle(context, 'Color Scheme'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ValueListenableBuilder<Color>(
                valueListenable: colorSeedNotifier,
                builder: (context, currentColor, _) {
                  final colors = [
                    Colors.blueGrey,
                    Colors.blue,
                    Colors.indigo,
                    Colors.teal,
                    Colors.green,
                    Colors.orange,
                    Colors.deepOrange,
                    Colors.red,
                    Colors.pink,
                    Colors.purple,
                  ];
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: colors.map((color) {
                      final isSelected = currentColor.value == color.value;
                      return GestureDetector(
                        onTap: () => colorSeedNotifier.value = color,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: isSelected ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 3) : null,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
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
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
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
