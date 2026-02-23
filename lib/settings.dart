import 'package:flutter/material.dart';
import 'l10n/app_localizations.dart';
import 'main.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settings),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _buildSectionTitle(context, l10n.appearance),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
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
                              if (newMode != null) {
                                themeModeNotifier.value = newMode;
                              }
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
                  const Divider(height: 24),
                  Row(
                    children: [
                      const Icon(Icons.language),
                      const SizedBox(width: 16),
                      Expanded(child: Text(l10n.language)),
                      ValueListenableBuilder<Locale?>(
                        valueListenable: localeNotifier,
                        builder: (context, locale, _) {
                          // Ensure the current value is one of the available options.
                          // If the current locale is not in the list (e.g., a base 'zh'),
                          // map it to null (System Default) to prevent the crash.
                          final availableItems = <Locale?>[null, const Locale('en'), const Locale('zh', 'TW'), const Locale('zh', 'CN')];
                          final dropdownValue = availableItems.contains(locale) ? locale : null;

                          return DropdownButton<Locale?>(
                            value: dropdownValue,
                            underline: const SizedBox(),
                            hint: Text(l10n.systemDefault),
                            onChanged: (Locale? newLocale) {
                              localeNotifier.value = newLocale;
                            },
                            items: availableItems.map((l) {
                              return DropdownMenuItem(value: l, child: Text(_getLocaleName(l, l10n)));
                            }).toList(),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildSectionTitle(context, l10n.colorScheme),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ValueListenableBuilder<Color>(
                valueListenable: colorSeedNotifier,
                builder: (context, currentColor, _) {
                  // A curated list of visually comfortable colors.
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
                            border: isSelected ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 3) : null,
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
          ),
          const SizedBox(height: 24),
          _buildSectionTitle(context, l10n.actions),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
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

  String _getLocaleName(Locale? locale, AppLocalizations l10n) {
    if (locale == null) {
      return l10n.systemDefault;
    }
    switch (locale.languageCode) {
      case 'en':
        return l10n.english;
      case 'zh':
        switch (locale.countryCode) {
          case 'TW':
            return l10n.traditionalChinese;
          case 'CN':
            return l10n.simplifiedChinese;
        }
    }
    // Fallback for any other locale
    return locale.toLanguageTag();
  }

  Future<void> _showResetConfirmationDialog(BuildContext context) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        final l10n = AppLocalizations.of(dialogContext)!;
        return AlertDialog(
          title: Text(l10n.resetSettingsConfirmationTitle),
          content: Text(l10n.resetSettingsConfirmationContent),
          actions: <Widget>[
            TextButton(
              child: Text(l10n.cancel),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            TextButton(
              child: Text(l10n.reset, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              onPressed: () {
                // Reset the notifiers to their default values
                themeModeNotifier.value = ThemeMode.light;
                colorSeedNotifier.value = Colors.blueGrey;
                localeNotifier.value = null;
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        );
      },
    );
  }
}

