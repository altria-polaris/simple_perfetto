import 'dart:io';
import 'package:flutter/material.dart';

class CallStackScreen extends StatelessWidget {
  const CallStackScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Call Stack Recorder'),
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.transform, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('Call Stack Recorder'),
          ],
        ),
      ),
    );
  }
}