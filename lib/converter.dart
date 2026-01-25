import 'dart:io';
import 'package:flutter/material.dart';

class TraceConverterScreen extends StatelessWidget {
  const TraceConverterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfetto Trace to Atrace'),
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.transform, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('Perfetto Trace to Atrace Converter'),
          ],
        ),
      ),
    );
  }
}