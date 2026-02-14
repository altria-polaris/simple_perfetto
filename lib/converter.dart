import 'package:flutter/material.dart';
import 'l10n/app_localizations.dart';

class TraceConverterScreen extends StatelessWidget {
  const TraceConverterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.converterTitle),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.transform, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(l10n.converterMessage),
          ],
        ),
      ),
    );
  }
}