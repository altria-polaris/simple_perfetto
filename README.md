# Simple Perfetto Recorder

**English** | [繁體中文](README.zh-TW.md)

**Simple Perfetto Recorder** is a cross-platform desktop application built with Flutter (optimized for Windows), designed to provide a clean graphical interface for recording, managing, and converting system traces.

This project simplifies the workflow for Perfetto and Atrace, offering an intuitive settings interface and automatic update capabilities.

## Features

### 1. Performance Recording (Record)
*   GUI controls to start and stop recording.
*   Configurable Max Duration.
*   Configurable Buffer Size.
*   Custom output file path.
*   Quick Presets and custom Atrace/Ftrace events.
*   Support for specifying User Process/Package Names.

### 2. Format Conversion (Convert)
*   Built-in **Perfetto Trace to Atrace** converter.
*   Easily convert Perfetto formats to formats readable by legacy tools.

### 3. Call Stack Analysis
*   Provides Call Stack visualization or analysis (inferred based on UI tags).

### 4. Customization
*   **Theme Switching**: Supports Light, Dark, and System modes.
*   **Color Schemes**: Multiple seed colors (Indigo, Blue, Orange, Green, Brown).
*   **Localization**: Currently supports English and Traditional/Simplified Chinese.

### 5. App Updates
*   **Auto-Update Mechanism**: Supports checking for updates from a Windows local path or network share (UNC Path, e.g., `\\server\share`).
*   Automatically downloads ZIP packages, extracts them, and uses a Batch Script to restart the application and complete the update.

## Tech Stack

*   **Framework**: Flutter (SDK ^3.5.3)
*   **Language**: Dart
*   **Window Management**: `window_manager` (Fixed window size 600x600, non-resizable)
*   **State Management**: `ValueNotifier` (Native simple state management)
*   **Local Storage**: `shared_preferences`
*   **File Handling**: `path_provider`, `archive` (for extracting updates)
*   **Localization**: `flutter_localizations`, `intl`

## Getting Started

### Prerequisites
*   Flutter SDK installed
*   Windows environment (Recommended, as the update mechanism includes Windows Batch Scripts)

### Install Dependencies
```bash
flutter pub get
