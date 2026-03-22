// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get settings => '設定';

  @override
  String get appearance => '外觀';

  @override
  String get themeMode => '主題模式';

  @override
  String get language => '語言';

  @override
  String get colorScheme => '色彩主題';

  @override
  String get actions => '操作';

  @override
  String get resetToDefaults => '重設為預設值';

  @override
  String get record => '錄製';

  @override
  String get callStack => '呼叫堆疊';

  @override
  String get convert => '轉換';

  @override
  String get about => '關於';

  @override
  String get systemDefault => '系統預設';

  @override
  String get english => 'English';

  @override
  String get traditionalChinese => '繁體中文';

  @override
  String get simplifiedChinese => '简体中文';

  @override
  String get themeModeSystem => '系統預設';

  @override
  String get themeModeLight => '淺色';

  @override
  String get themeModeDark => '深色';

  @override
  String get resetSettingsConfirmationTitle => '重設設定？';

  @override
  String get resetSettingsConfirmationContent => '這會將所有外觀設定重設為預設值。此操作無法復原。';

  @override
  String get cancel => '取消';

  @override
  String get reset => '重設';

  @override
  String get appTitle => 'Perfetto Trace Recorder';

  @override
  String get noDevice => 'No Device';

  @override
  String get refreshDevices => '重新整理裝置';

  @override
  String get start => '開始';

  @override
  String get stop => '停止';

  @override
  String get maxDuration => '最大長度';

  @override
  String get bufferSize => '緩衝區大小';

  @override
  String get outputTraceFile => '輸出 Trace 檔案';

  @override
  String get openExplorer => '開啟檔案總管';

  @override
  String get openPerfetto => '開啟 Perfetto';

  @override
  String get fontFamily => 'Microsoft JhengHei UI';

  @override
  String get updates => '更新';

  @override
  String get checkForUpdates => '檢查更新';

  @override
  String get updateAvailable => '有可用更新';

  @override
  String get upToDate => '已是最新版本';

  @override
  String get download => '下載更新';

  @override
  String get installAndRestart => '安裝並重啟';

  @override
  String get errorCheckingUpdate => '檢查更新時發生錯誤';

  @override
  String get version => '版本';

  @override
  String get recordingInProgress => '正在錄製中...';

  @override
  String get startingPerfetto => '正在啟動 Perfetto...';

  @override
  String get startingCallstack => '正在啟動 Perfetto (CallStack)...';

  @override
  String get recordingFinishedPulling => '錄製完成。正在傳輸檔案...';

  @override
  String get stoppingManually => '正在手動停止...';

  @override
  String successSavedTo(Object path) {
    return '成功！已儲存至 $path';
  }

  @override
  String pullFailed(Object error) {
    return '傳輸失敗: $error';
  }

  @override
  String errorStartingProcess(Object error) {
    return '啟動程序失敗: $error';
  }

  @override
  String perfettoError(Object code) {
    return '錯誤: Perfetto 以代碼 $code 結束';
  }

  @override
  String errorPullingFile(Object error) {
    return '抓取檔案失敗: $error';
  }

  @override
  String errorGettingDevices(Object error) {
    return '取得裝置清單失敗: $error';
  }

  @override
  String ftraceFormatError(Object token) {
    return '錯誤: Ftrace 事件 \"$token\" 必須符合 \"category/event\" 格式。';
  }

  @override
  String fileNotFound(Object filename) {
    return '找不到檔案: $filename';
  }

  @override
  String get servingTrace => '正透過連接埠9001開啟Trace...';

  @override
  String errorStartingServer(Object error) {
    return '啟動伺服器失敗: $error';
  }

  @override
  String get fetchingTopApp => '正在取得前景APP名稱...';

  @override
  String addedApp(Object app) {
    return '已加入 $app';
  }

  @override
  String get couldNotDetermineTopApp => '無法取得前景APP名稱';

  @override
  String genericError(Object error) {
    return '錯誤: $error';
  }

  @override
  String get manualEditsHint => '此處手動編輯的配置將會被沿用到下次錄製。';

  @override
  String get goToSettings => '移動到設定';
}

/// The translations for Chinese, as used in China (`zh_CN`).
class AppLocalizationsZhCn extends AppLocalizationsZh {
  AppLocalizationsZhCn(): super('zh_CN');

  @override
  String get settings => '设置';

  @override
  String get appearance => '外观';

  @override
  String get themeMode => '主题模式';

  @override
  String get language => '语言';

  @override
  String get colorScheme => '色彩主题';

  @override
  String get actions => '操作';

  @override
  String get resetToDefaults => '重置为默认值';

  @override
  String get record => '录制';

  @override
  String get callStack => '调用栈';

  @override
  String get convert => '转换';

  @override
  String get about => '关于';

  @override
  String get systemDefault => '系统默认';

  @override
  String get english => 'English';

  @override
  String get traditionalChinese => '繁體中文';

  @override
  String get simplifiedChinese => '简体中文';

  @override
  String get themeModeSystem => '系统默认';

  @override
  String get themeModeLight => '浅色';

  @override
  String get themeModeDark => '深色';

  @override
  String get resetSettingsConfirmationTitle => '重置设置？';

  @override
  String get resetSettingsConfirmationContent => '这会将所有外观设置重置为默认值。此操作无法复原。';

  @override
  String get cancel => '取消';

  @override
  String get reset => '重置';

  @override
  String get appTitle => 'Perfetto Trace Recorder';

  @override
  String get noDevice => '无设备';

  @override
  String get refreshDevices => '刷新设备';

  @override
  String get start => '开始';

  @override
  String get stop => '停止';

  @override
  String get maxDuration => '最大时长';

  @override
  String get bufferSize => '缓冲区大小';

  @override
  String get outputTraceFile => '输出 Trace 文件';

  @override
  String get openExplorer => '打开文件管理器';

  @override
  String get openPerfetto => '打开 Perfetto';

  @override
  String get fontFamily => 'Microsoft JhengHei UI';

  @override
  String get updates => '更新';

  @override
  String get checkForUpdates => '检查更新';

  @override
  String get updateAvailable => '有可用更新';

  @override
  String get upToDate => '已是最新版本';

  @override
  String get download => '下载更新';

  @override
  String get installAndRestart => '安装并重启';

  @override
  String get errorCheckingUpdate => '检查更新时发生错误';

  @override
  String get version => '版本';

  @override
  String get recordingInProgress => '正在录制中...';

  @override
  String get startingPerfetto => '正在启动 Perfetto...';

  @override
  String get startingCallstack => '正在启动 Perfetto (CallStack)...';

  @override
  String get recordingFinishedPulling => '录制完成。正在传输文件...';

  @override
  String get stoppingManually => '正在手动停止...';

  @override
  String successSavedTo(Object path) {
    return '成功！已保存至 $path';
  }

  @override
  String pullFailed(Object error) {
    return '传输失败: $error';
  }

  @override
  String errorStartingProcess(Object error) {
    return '启动程序失败: $error';
  }

  @override
  String perfettoError(Object code) {
    return '错误: Perfetto 以代码 $code 结束';
  }

  @override
  String errorPullingFile(Object error) {
    return '抓取文件失败: $error';
  }

  @override
  String errorGettingDevices(Object error) {
    return '获取设备列表失败: $error';
  }

  @override
  String ftraceFormatError(Object token) {
    return '错误: Ftrace 事件 \"$token\" 必须符合 \"category/event\" 格式。';
  }

  @override
  String fileNotFound(Object filename) {
    return '找不到文件: $filename';
  }

  @override
  String get servingTrace => '正通过端口9001启动Trace...';

  @override
  String errorStartingServer(Object error) {
    return '启动服务器失败: $error';
  }

  @override
  String get fetchingTopApp => '正在获取前景APP名称...';

  @override
  String addedApp(Object app) {
    return '已加入 $app';
  }

  @override
  String get couldNotDetermineTopApp => '无法获取前景APP名称';

  @override
  String genericError(Object error) {
    return '错误: $error';
  }

  @override
  String get manualEditsHint => '此处手动编辑的配置将会被沿用到下次录制。';

  @override
  String get goToSettings => '移动到设置';
}
