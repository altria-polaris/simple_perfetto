# Simple Perfetto Recorder

[English](README.md) | **繁體中文**

**Simple Perfetto Recorder** 是一個基於 Flutter 開發的跨平台桌面應用程式（主要針對 Windows 優化），旨在提供一個簡潔的圖形化介面來錄製、管理與轉換系統效能追蹤檔案 (System Traces)。

本專案簡化了 Perfetto 與 Atrace 的操作流程，並提供直覺的設定介面與自動更新功能。

## 主要功能 (Features)

### 1. 效能錄製 (Record)
*   提供圖形化介面控制錄製開始與停止。
*   支援設定最大錄製時間 (Max Duration)。
*   支援設定緩衝區大小 (Buffer Size)。
*   自訂輸出檔案路徑。
*   快速預設設定 (Quick Presets) 與自訂 Atrace/Ftrace 事件。
*   支援指定 User Process/Package Names。

### 2. 格式轉換 (Convert)
*   內建 **Perfetto Trace to Atrace** 轉換器。
*   方便將 Perfetto 格式轉換為舊版工具可讀取的格式。

### 3. 堆疊分析 (Call Stack)
*   提供 Call Stack 視覺化或分析功能（依據 UI 標籤推斷）。

### 4. 個人化設定 (Customization)
*   **主題切換**：支援淺色 (Light)、深色 (Dark) 及跟隨系統 (System) 模式。
*   **色彩主題**：提供多種種子顏色 (Indigo, Blue, Orange, Green, Brown) 供選擇。
*   **多語言支援**：目前支援英文 (English) 與繁體/簡體中文。

### 5. 應用程式更新 (App Updates)
*   **自動更新機制**：支援從 Windows 本地路徑或網路共用路徑 (UNC Path, e.g., `\\server\share`) 檢查更新。
*   自動下載 ZIP 更新包、解壓縮，並透過批次檔 (Batch Script) 自動重啟應用程式以完成更新。

## 技術堆疊 (Tech Stack)

*   **Framework**: Flutter (SDK ^3.5.3)
*   **Language**: Dart
*   **Window Management**: `window_manager` (固定視窗大小 600x600，不可調整大小)
*   **State Management**: `ValueNotifier` (原生簡單狀態管理)
*   **Local Storage**: `shared_preferences`
*   **File Handling**: `path_provider`, `archive` (用於解壓更新檔)
*   **Localization**: `flutter_localizations`, `intl`

## 快速開始 (Getting Started)

### 前置需求
*   Flutter SDK installed
*   Windows 環境 (推薦，因更新機制包含 Windows Batch Script)

### 安裝依賴
```bash
flutter pub get
```

### 執行專案
```bash
flutter run
```

### 建置發布 (Windows)
```bash
flutter build windows
```

## 設定更新路徑 (Update Configuration)

本專案包含一個基於檔案系統的更新機制。在編譯前，請務必修改 `lib/settings.dart` 中的更新來源路徑：

```dart
// lib/settings.dart

// 修改此處為您的更新伺服器路徑或共用資料夾路徑
const String _kUpdateUrl = r'\\server\share\updates'; 
// 或本地測試路徑: r'C:\updates'
```

**更新伺服器結構要求：**
該路徑下需包含：
1.  `version.json`：描述版本資訊。
2.  更新的 ZIP 壓縮檔（檔名需與 json 內描述一致）。

**version.json 範例：**
```json
{
  "version": "1.0.0",
  "build": "2",
  "path": "update_package.zip"
}
```

## 專案結構

*   `lib/main.dart`: 應用程式入口，包含視窗初始化、主題載入與主導航 (NavigationRail)。
*   `lib/settings.dart`: 設定頁面，包含外觀設定與**更新檢查邏輯**。
*   `lib/l10n/`: 多語言定義檔。
*   `lib/recorder.dart`: (推測) 錄製功能實作。
*   `lib/converter.dart`: (推測) 轉換功能實作。
